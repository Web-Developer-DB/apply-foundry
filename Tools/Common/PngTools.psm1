#requires -Version 7.6
#requires -PSEdition Core

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if (-not ('ApplyFoundry.Imaging.PortablePngReader' -as [type])) {
  Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Text;

namespace ApplyFoundry.Imaging
{
    public sealed class PngImageData
    {
        public int Width { get; internal set; }
        public int Height { get; internal set; }
        public byte BitDepth { get; internal set; }
        public byte ColorType { get; internal set; }
        public int Channels { get; internal set; }
        public int Stride { get; internal set; }
        public byte[] Pixels { get; internal set; }

        public byte[] GetRgba(int x, int y)
        {
            if (x < 0 || x >= Width) throw new ArgumentOutOfRangeException(nameof(x));
            if (y < 0 || y >= Height) throw new ArgumentOutOfRangeException(nameof(y));
            int offset = checked(y * Stride + x * Channels);
            if (ColorType == 0)
            {
                byte gray = Pixels[offset];
                return new[] { gray, gray, gray, (byte)255 };
            }
            if (ColorType == 2)
            {
                return new[] { Pixels[offset], Pixels[offset + 1], Pixels[offset + 2], (byte)255 };
            }
            return new[] { Pixels[offset], Pixels[offset + 1], Pixels[offset + 2], Pixels[offset + 3] };
        }
    }

    public static class PortablePngReader
    {
        private static readonly byte[] Signature = { 137, 80, 78, 71, 13, 10, 26, 10 };
        private static readonly uint[] CrcTable = BuildCrcTable();

        public static PngImageData Read(string path, long maximumPixels)
        {
            if (String.IsNullOrWhiteSpace(path)) throw new ArgumentException("PNG path is required.", nameof(path));
            if (maximumPixels < 1) throw new ArgumentOutOfRangeException(nameof(maximumPixels));

            using (var input = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read))
            using (var reader = new BinaryReader(input, Encoding.ASCII, true))
            using (var compressed = new MemoryStream())
            {
                if (input.Length > 268435456L) throw new InvalidDataException("PNG file exceeds the 256 MiB safety limit.");
                byte[] signature = ReadExact(reader, Signature.Length);
                for (int index = 0; index < Signature.Length; index++)
                    if (signature[index] != Signature[index]) throw new InvalidDataException("Invalid PNG signature.");

                int width = 0, height = 0, channels = 0;
                byte bitDepth = 0, colorType = 0;
                bool seenHeader = false, seenData = false, seenEnd = false;

                while (!seenEnd)
                {
                    if (input.Length - input.Position < 12) throw new InvalidDataException("Truncated PNG chunk.");
                    uint chunkLengthValue = ReadUInt32BigEndian(reader);
                    if (chunkLengthValue > Int32.MaxValue) throw new InvalidDataException("PNG chunk is too large.");
                    int chunkLength = (int)chunkLengthValue;
                    byte[] typeBytes = ReadExact(reader, 4);
                    string chunkType = Encoding.ASCII.GetString(typeBytes);
                    byte[] data = ReadExact(reader, chunkLength);
                    uint storedCrc = ReadUInt32BigEndian(reader);
                    uint actualCrc = ComputeCrc(typeBytes, data);
                    if (storedCrc != actualCrc) throw new InvalidDataException("PNG chunk CRC mismatch: " + chunkType + ".");

                    switch (chunkType)
                    {
                        case "IHDR":
                            if (seenHeader || input.Position != 33 || data.Length != 13)
                                throw new InvalidDataException("PNG must contain exactly one leading IHDR chunk.");
                            width = ReadInt32BigEndian(data, 0);
                            height = ReadInt32BigEndian(data, 4);
                            bitDepth = data[8];
                            colorType = data[9];
                            if (width < 1 || height < 1) throw new InvalidDataException("PNG dimensions must be positive.");
                            if ((long)width * height > maximumPixels) throw new InvalidDataException("PNG exceeds the configured pixel limit.");
                            if (bitDepth != 8) throw new InvalidDataException("Only 8-bit PNG images are supported.");
                            channels = colorType == 0 ? 1 : colorType == 2 ? 3 : colorType == 6 ? 4 : 0;
                            if (channels == 0) throw new InvalidDataException("Only grayscale, RGB and RGBA PNG images are supported.");
                            if (data[10] != 0 || data[11] != 0) throw new InvalidDataException("Unsupported PNG compression or filter method.");
                            if (data[12] != 0) throw new InvalidDataException("Interlaced PNG images are not supported.");
                            seenHeader = true;
                            break;
                        case "IDAT":
                            if (!seenHeader) throw new InvalidDataException("PNG IDAT appeared before IHDR.");
                            if (data.Length > 0) compressed.Write(data, 0, data.Length);
                            seenData = true;
                            break;
                        case "IEND":
                            if (!seenHeader || !seenData || data.Length != 0) throw new InvalidDataException("Invalid PNG IEND chunk.");
                            seenEnd = true;
                            break;
                        default:
                            bool critical = typeBytes[0] >= (byte)'A' && typeBytes[0] <= (byte)'Z';
                            if (critical && chunkType != "PLTE") throw new InvalidDataException("Unsupported critical PNG chunk: " + chunkType + ".");
                            break;
                    }
                }
                if (input.Position != input.Length) throw new InvalidDataException("Trailing data after PNG IEND chunk is not allowed.");

                int stride = checked(width * channels);
                int encodedStride = checked(stride + 1);
                int encodedLength = checked(encodedStride * height);
                byte[] filtered = new byte[encodedLength];
                compressed.Position = 0;
                using (var zlib = new ZLibStream(compressed, CompressionMode.Decompress, true))
                {
                    ReadStreamExactly(zlib, filtered, 0, filtered.Length);
                    if (zlib.ReadByte() != -1) throw new InvalidDataException("PNG decompressed data exceeds expected dimensions.");
                }

                byte[] pixels = new byte[checked(stride * height)];
                for (int y = 0; y < height; y++)
                {
                    int sourceOffset = y * encodedStride;
                    byte filter = filtered[sourceOffset];
                    if (filter > 4) throw new InvalidDataException("Unsupported PNG row filter: " + filter + ".");
                    int destinationOffset = y * stride;
                    for (int x = 0; x < stride; x++)
                    {
                        int raw = filtered[sourceOffset + 1 + x];
                        int left = x >= channels ? pixels[destinationOffset + x - channels] : 0;
                        int up = y > 0 ? pixels[destinationOffset - stride + x] : 0;
                        int upperLeft = y > 0 && x >= channels ? pixels[destinationOffset - stride + x - channels] : 0;
                        int value;
                        switch (filter)
                        {
                            case 0: value = raw; break;
                            case 1: value = raw + left; break;
                            case 2: value = raw + up; break;
                            case 3: value = raw + ((left + up) / 2); break;
                            default: value = raw + Paeth(left, up, upperLeft); break;
                        }
                        pixels[destinationOffset + x] = (byte)(value & 255);
                    }
                }

                return new PngImageData
                {
                    Width = width,
                    Height = height,
                    BitDepth = bitDepth,
                    ColorType = colorType,
                    Channels = channels,
                    Stride = stride,
                    Pixels = pixels
                };
            }
        }

        private static int Paeth(int left, int up, int upperLeft)
        {
            int estimate = left + up - upperLeft;
            int leftDistance = Math.Abs(estimate - left);
            int upDistance = Math.Abs(estimate - up);
            int upperLeftDistance = Math.Abs(estimate - upperLeft);
            if (leftDistance <= upDistance && leftDistance <= upperLeftDistance) return left;
            if (upDistance <= upperLeftDistance) return up;
            return upperLeft;
        }

        private static byte[] ReadExact(BinaryReader reader, int count)
        {
            byte[] value = reader.ReadBytes(count);
            if (value.Length != count) throw new EndOfStreamException("Unexpected end of PNG data.");
            return value;
        }

        private static void ReadStreamExactly(Stream stream, byte[] buffer, int offset, int count)
        {
            while (count > 0)
            {
                int read = stream.Read(buffer, offset, count);
                if (read == 0) throw new InvalidDataException("PNG decompressed data is shorter than expected.");
                offset += read;
                count -= read;
            }
        }

        private static uint ReadUInt32BigEndian(BinaryReader reader)
        {
            byte[] value = ReadExact(reader, 4);
            return ((uint)value[0] << 24) | ((uint)value[1] << 16) | ((uint)value[2] << 8) | value[3];
        }

        private static int ReadInt32BigEndian(byte[] value, int offset)
        {
            uint result = ((uint)value[offset] << 24) | ((uint)value[offset + 1] << 16) |
                          ((uint)value[offset + 2] << 8) | value[offset + 3];
            if (result > Int32.MaxValue) throw new InvalidDataException("PNG dimension exceeds supported integer range.");
            return (int)result;
        }

        private static uint[] BuildCrcTable()
        {
            var table = new uint[256];
            for (uint index = 0; index < table.Length; index++)
            {
                uint value = index;
                for (int bit = 0; bit < 8; bit++)
                    value = (value & 1) != 0 ? 0xedb88320U ^ (value >> 1) : value >> 1;
                table[index] = value;
            }
            return table;
        }

        private static uint ComputeCrc(byte[] type, byte[] data)
        {
            uint crc = 0xffffffffU;
            foreach (byte value in type) crc = CrcTable[(crc ^ value) & 0xff] ^ (crc >> 8);
            foreach (byte value in data) crc = CrcTable[(crc ^ value) & 0xff] ^ (crc >> 8);
            return crc ^ 0xffffffffU;
        }
    }
}
'@
}

function Read-PngImage {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$LiteralPath,
    [ValidateRange(1, 100000000)][long]$MaxPixels = 50000000
  )

  if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
    throw "PNG-Datei wurde nicht gefunden: $LiteralPath"
  }
  $resolvedPath = (Resolve-Path -LiteralPath $LiteralPath).Path
  if ([System.IO.Path]::GetExtension($resolvedPath) -ine '.png') {
    throw "Datei besitzt nicht die Erweiterung .png: $resolvedPath"
  }
  return [ApplyFoundry.Imaging.PortablePngReader]::Read($resolvedPath, $MaxPixels)
}

function Get-PngPixel {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][ApplyFoundry.Imaging.PngImageData]$Image,
    [Parameter(Mandatory)][int]$X,
    [Parameter(Mandatory)][int]$Y
  )

  $rgba = $Image.GetRgba($X, $Y)
  return [pscustomobject][ordered]@{
    R = [int]$rgba[0]
    G = [int]$rgba[1]
    B = [int]$rgba[2]
    A = [int]$rgba[3]
  }
}

function Test-PngImage {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$LiteralPath,
    [ValidateRange(0, [int]::MaxValue)][int]$ExpectedWidth = 0,
    [ValidateRange(0, [int]::MaxValue)][int]$ExpectedHeight = 0,
    [ValidateRange(1, 100000000)][long]$MaxPixels = 50000000
  )

  try {
    $image = Read-PngImage -LiteralPath $LiteralPath -MaxPixels $MaxPixels
    if ($ExpectedWidth -gt 0 -and $image.Width -ne $ExpectedWidth) {
      throw "PNG-Breite ist $($image.Width), erwartet wurde $ExpectedWidth."
    }
    if ($ExpectedHeight -gt 0 -and $image.Height -ne $ExpectedHeight) {
      throw "PNG-Höhe ist $($image.Height), erwartet wurde $ExpectedHeight."
    }
    return [pscustomobject][ordered]@{
      valid = $true
      width = $image.Width
      height = $image.Height
      bitDepth = $image.BitDepth
      colorType = $image.ColorType
      channels = $image.Channels
      error = $null
    }
  } catch {
    return [pscustomobject][ordered]@{
      valid = $false
      width = $null
      height = $null
      bitDepth = $null
      colorType = $null
      channels = $null
      error = $_.Exception.Message
    }
  }
}

function Measure-PngBottomWhitespace {
  [CmdletBinding()]
  param(
    [Parameter(Mandatory)][string]$LiteralPath,
    [Parameter(Mandatory)][string]$DocumentName,
    [ValidateRange(1, [int]::MaxValue)][int]$PageNumber = 1,
    [ValidateRange(1, [int]::MaxValue)][int]$PageCount = 1,
    [ValidateRange(0.0, 297.0)][double]$BottomReserveMm = 12.0
  )

  $result = [ordered]@{
    available = $false
    bottomWhitespacePx = $null
    bottomWhitespaceMm = $null
    pageNumber = $PageNumber
    pageCount = $PageCount
    scanBottomReserveMm = $BottomReserveMm
    warning = $null
  }

  try {
    $image = Read-PngImage -LiteralPath $LiteralPath
    $lastInkRow = -1
    $left = [math]::Max(8, [int]($image.Width * 0.03))
    $right = [math]::Min($image.Width - 9, [int]($image.Width * 0.97))
    if ($right -lt $left) {
      throw 'PNG ist für die Layoutdichteprüfung zu schmal.'
    }
    $reservePx = [math]::Max(2, [int][math]::Round(($BottomReserveMm * $image.Height) / 297.0))
    $scanBottom = [math]::Max(0, ($image.Height - 1) - $reservePx)

    for ($y = $scanBottom; $y -ge 0; $y--) {
      $inkSamples = 0
      for ($x = $left; $x -le $right; $x += 2) {
        $offset = $y * $image.Stride + $x * $image.Channels
        if ($image.ColorType -eq 0) {
          $red = $green = $blue = [int]$image.Pixels[$offset]
          $alpha = 255
        } else {
          $red = [int]$image.Pixels[$offset]
          $green = [int]$image.Pixels[$offset + 1]
          $blue = [int]$image.Pixels[$offset + 2]
          $alpha = if ($image.ColorType -eq 6) { [int]$image.Pixels[$offset + 3] } else { 255 }
        }
        # Transparente Pixel werden gegen Weiß komponiert, wie sie im Screenshot sichtbar sind.
        if ($alpha -lt 255) {
          $red = [int][math]::Round((($red * $alpha) + (255 * (255 - $alpha))) / 255.0)
          $green = [int][math]::Round((($green * $alpha) + (255 * (255 - $alpha))) / 255.0)
          $blue = [int][math]::Round((($blue * $alpha) + (255 * (255 - $alpha))) / 255.0)
        }
        if ($red -lt 242 -or $green -lt 242 -or $blue -lt 242) {
          $inkSamples++
          if ($inkSamples -ge 2) {
            $lastInkRow = $y
            break
          }
        }
      }
      if ($lastInkRow -ge 0) { break }
    }

    if ($lastInkRow -ge 0) {
      $whitespacePx = $scanBottom - $lastInkRow
      $whitespaceMm = [math]::Round(($whitespacePx * 297.0) / $image.Height, 1)
      $result.available = $true
      $result.bottomWhitespacePx = $whitespacePx
      $result.bottomWhitespaceMm = $whitespaceMm
      $maximumWhitespaceMm = if ($DocumentName -like 'Lebenslauf -*') { 55.0 } else { 70.0 }
      if ($whitespaceMm -gt $maximumWhitespaceMm) {
        $result.warning = "Seite $PageNumber von $PageCount hat ungewöhnlich viel freie Fläche im nutzbaren Inhaltsbereich: $whitespaceMm mm."
      } elseif ($whitespaceMm -lt 4.0) {
        $result.warning = "Inhalt auf Seite $PageNumber von $PageCount liegt mit nur $whitespaceMm mm Abstand nahe an der unteren Inhaltsgrenze."
      }
    } else {
      $result.warning = "Auf Seite $PageNumber von $PageCount wurde im nutzbaren Inhaltsbereich kein auswertbarer Inhalt erkannt."
    }
  } catch {
    $result.warning = "Layoutdichte konnte nicht automatisch ausgewertet werden: $($_.Exception.Message)"
  }
  return [pscustomobject]$result
}

Export-ModuleMember -Function @(
  'Read-PngImage',
  'Get-PngPixel',
  'Test-PngImage',
  'Measure-PngBottomWhitespace'
)
