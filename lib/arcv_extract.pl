#!/usr/bin/perl
# Unpack an ARCV archive: the container of InstallWrap, the installer on the
# Colonization for Windows CD, which ships COLONIZE.EXE compressed as INSTALL/COLONIZE._00.
#
#   perl arcv_extract.pl ARCHIVE OUTPUT
#
# Perl because macOS and Linux both ship it, so setting up from a CD image needs
# nothing installed. docs/cd-image.md has the format and where it was established.
#
# Container, one member in one chunk:
#   0x00  "ARCV"
#   0x04  WORD   version, 0x0110
#   0x06  WORD   offset of the CHNK header
#   0x0c  BYTE   length of the member name, which follows at 0x0d
#   then  DWORD  uncompressed size, DWORD compressed size
#   CHNK  a 16-byte header, then the payload, which runs to the end of the file
#
# Payload: LZHUF (adaptive Huffman over a 4096-byte LZSS window) in InstallWrap's
# variant: 287 symbols (256 literals, an end marker, 30 match lengths), and a ring
# prefilled with spaces whose write position starts at 0xdc3. The position tables
# are LZHUF's standard ones, generated below rather than copied.
use strict;
use warnings;

@ARGV == 2 or die "usage: arcv_extract.pl ARCHIVE OUTPUT\n";
my ($in, $out) = @ARGV;

open my $fh, '<:raw', $in or die "$in: $!\n";
my $b = do { local $/; <$fh> };
close $fh;

substr($b, 0, 4) eq 'ARCV' or die "$in: not an ARCV archive\n";
my ($version, $chunk) = unpack 'v v', substr($b, 4, 4);
$version == 0x0110 or die sprintf "%s: ARCV version 0x%04x, expected 0x0110\n", $in, $version;
my $name_len = ord substr($b, 0x0c, 1);
my ($usize, $csize) = unpack 'V V', substr($b, 0x0d + $name_len, 8);
substr($b, $chunk, 4) eq 'CHNK' or die "$in: no CHNK header at offset $chunk\n";
my $off = $chunk + 16;
$off + $csize == length $b
    or die "$in: the payload does not end at the end of the file; only one member in one chunk is supported\n";
my @in = unpack 'C*', substr($b, $off, $csize);
my $in_len = @in;

my ($N, $T, $N_CHAR, $R, $MAX_FREQ) = (4096, 573, 287, 572, 0x8000);

# Position tables: the upper 6 bits of a match position are coded in 3 to 8 bits.
my (@d_code, @d_len);
{
    my $code = 0;
    for my $group ([3, 1], [4, 3], [5, 8], [6, 12], [7, 24], [8, 16]) {
        my ($len, $codes) = @$group;
        for (1 .. $codes) {
            for (1 .. 1 << (8 - $len)) { push @d_code, $code; push @d_len, $len; }
            $code++;
        }
    }
}

# The Huffman tree: leaves are T + symbol, freq[T] is a sentinel.
my (@freq, @son, @prnt);
for my $i (0 .. $N_CHAR - 1) { $freq[$i] = 1; $son[$i] = $i + $T; $prnt[$i + $T] = $i; }
for (my ($i, $j) = (0, $N_CHAR); $j <= $R; $i += 2, $j++) {
    $freq[$j] = $freq[$i] + $freq[$i + 1];
    $son[$j] = $i;
    $prnt[$i] = $prnt[$i + 1] = $j;
}
$freq[$T] = 0xffff;
$prnt[$R] = 0;

# Halve every frequency and rebuild the tree, once the root reaches MAX_FREQ.
sub reconst {
    my $j = 0;
    for my $i (0 .. $T - 1) {
        next unless $son[$i] >= $T;
        $freq[$j] = ($freq[$i] + 1) >> 1;
        $son[$j] = $son[$i];
        $j++;
    }
    for (my ($i, $j) = (0, $N_CHAR); $j < $T; $i += 2, $j++) {
        my $f = $freq[$i] + $freq[$i + 1];
        my $k = $j - 1;
        $k-- while $f < $freq[$k];
        $k++;
        @freq[$k + 1 .. $j] = @freq[$k .. $j - 1];
        $freq[$k] = $f;
        @son[$k + 1 .. $j] = @son[$k .. $j - 1];
        $son[$k] = $i;
    }
    for my $i (0 .. $T - 1) {
        my $k = $son[$i];
        $prnt[$k] = $i;
        $prnt[$k + 1] = $i if $k < $T;
    }
}

# Count one occurrence of symbol c, keeping the tree ordered by frequency.
sub update {
    my $c = shift;
    reconst() if $freq[$R] == $MAX_FREQ;
    $c = $prnt[$c + $T];
    do {
        my $k = ++$freq[$c];
        my $l = $c + 1;
        if ($k > $freq[$l]) {
            $l++ while $k > $freq[$l + 1];
            $freq[$c] = $freq[$l];
            $freq[$l] = $k;
            my $i = $son[$c];
            $prnt[$i] = $l;
            $prnt[$i + 1] = $l if $i < $T;
            my $j = $son[$l];
            $son[$l] = $i;
            $prnt[$j] = $c;
            $prnt[$j + 1] = $c if $j < $T;
            $son[$c] = $j;
            $c = $l;
        }
        $c = $prnt[$c];
    } while ($c != 0);
}

# The bit reader: a 16-bit buffer, most significant bit first. Reads past the end
# of the payload yield zeros, as InstallWrap's do.
my ($p, $buf, $n) = (0, 0, 0);
sub bit {
    if ($n == 0) {
        $buf = ($buf | (($p < $in_len ? $in[$p++] : 0) << 8)) & 0xffff;
        $n = 8;
    }
    $n--;
    my $v = ($buf >> 15) & 1;
    $buf = ($buf << 1) & 0xffff;
    return $v;
}
sub byte {
    if ($n < 8) {
        $buf = ($buf | (($p < $in_len ? $in[$p++] : 0) << (8 - $n))) & 0xffff;
        $n += 8;
    }
    my $v = ($buf >> 8) & 0xff;
    $n -= 8;
    $buf = ($buf << 8) & 0xffff;
    return $v;
}

my @text = (32) x $N;
my $r = 0xdc3;
my $o = '';
while (1) {
    my $c = $son[$R];
    $c = $son[$c + bit()] while $c < $T;
    $c -= $T;
    update($c);
    last if $c == 0x100;
    if ($c < 0x100) {
        $o .= chr $c;
        $text[$r] = $c;
        $r = ($r + 1) & ($N - 1);
        next;
    }
    my $i = byte();
    my $low = $i;
    $low = ($low << 1) | bit() for 1 .. $d_len[$i] - 2;
    my $src = ($r - (($d_code[$i] << 6) | ($low & 0x3f)) - 1) & ($N - 1);
    for my $k (0 .. $c - 0xff) {
        my $v = $text[($src + $k) & ($N - 1)];
        $o .= chr $v;
        $text[$r] = $v;
        $r = ($r + 1) & ($N - 1);
    }
}

length($o) == $usize
    or die sprintf "%s: unpacked %d bytes, but the header says %d\n", $in, length $o, $usize;
open my $oh, '>:raw', $out or die "$out: $!\n";
print $oh $o;
close $oh or die "$out: $!\n";
