#!/usr/bin/perl
# Maze autotiler + validator for Ms. Pac-Man (TI-99 XB256).
#
# Author a maze as a plain 28x22 grid of:  # wall   . dot   o power-pellet
#                                          (space) empty   D ghost-house door
# This emits the encoded DATA strings the game READs (see DESIGN.md S13):
#   wall  -> 'a'+mask     (mask = N*1 + E*2 + S*4 + W*8 over '#' neighbours)
#   dot . , pellet O , door D , empty (space)  -> passed through (o->O)
#
# It also VALIDATES:
#   - flood-fills from Ms. Pac-Man's start cell (DATA row 17, col 14) through
#     passable cells ('.', 'o', ' '); any unreachable dot/pellet is reported
#     and converted to empty (so no maze can trap dots).
#   - left/right symmetry about the vertical centre line.
#   - prints the dot+pellet count and a back-rendered picture.
#
# Usage: perl mazegen.pl <grid-file>

use strict; use warnings;

my $W = 28; my $H = 22;
my $PR = 16; my $PC = 13;   # Ms. Pac-Man start cell (0-indexed; = 1-indexed DATA row 17 col 14)

my $file = shift or die "usage: perl mazegen.pl <grid-file>\n";
open my $fh, '<', $file or die "open $file: $!\n";
my @raw = <$fh>; close $fh;
# strip the optional leading comment/legend block: keep only grid lines.
# A grid line is anything; we take the LAST $H non-empty lines as the grid.
chomp @raw;
@raw = grep { /\S/ || 1 } @raw;        # keep all (incl. blank rows in maze)
# take last H lines (lets the file have a header)
@raw = @raw[ -$H .. -1 ] if @raw > $H;
die "need $H grid rows, got ".scalar(@raw)."\n" unless @raw == $H;

# normalise each row to exactly W cells
my @g;
for my $r (0..$H-1) {
  my $line = $raw[$r];
  $line =~ s/o/o/g;                    # keep lowercase o as pellet marker
  my @c = split //, $line;
  push @c, ' ' while @c < $W;
  @c = @c[0..$W-1];
  # map any unknown char to space
  @c = map { /[#.oOD ]/ ? ($_ eq 'O' ? 'o' : $_) : ' ' } @c;
  push @g, \@c;
}

sub iswall { my ($r,$c)=@_; return 0 if $r<0||$r>=$H||$c<0||$c>=$W; return $g[$r][$c] eq '#'; }
sub ispass { my ($r,$c)=@_; return 0 if $r<0||$r>=$H||$c<0||$c>=$W; my $x=$g[$r][$c]; return ($x eq '.'||$x eq 'o'||$x eq ' '); }

# ---- flood fill from Pac start ----
die "Pac start ($PR,$PC) is not passable ('".$g[$PR][$PC]."')\n" unless ispass($PR,$PC);
my %seen; my @stk = ([$PR,$PC]);
while (@stk) {
  my ($r,$c) = @{ pop @stk };
  next if $seen{"$r,$c"}; $seen{"$r,$c"}=1;
  for my $d ([-1,0],[1,0],[0,-1],[0,1]) {
    my ($nr,$nc)=($r+$d->[0],$c+$d->[1]);
    push @stk,[$nr,$nc] if ispass($nr,$nc) && !$seen{"$nr,$nc"};
  }
}
my $unreach=0;
for my $r (0..$H-1) { for my $c (0..$W-1) {
  if (($g[$r][$c] eq '.'||$g[$r][$c] eq 'o') && !$seen{"$r,$c"}) { $unreach++; warn "  unreachable dot at row $r col $c -> cleared\n"; $g[$r][$c]=' '; }
}}

# ---- symmetry check ----
my $asym=0;
for my $r (0..$H-1) { for my $c (0..$W/2-1) {
  my $a=$g[$r][$c]; my $b=$g[$r][$W-1-$c];
  my $ca = $a eq '#' ? '#' : $a eq 'D' ? 'D' : 'o'; # class: wall/door/open
  my $cb = $b eq '#' ? '#' : $b eq 'D' ? 'D' : 'o';
  if ($ca ne $cb) { $asym++; warn "  asymmetry row $r col $c ('$a') vs col ".($W-1-$c)." ('$b')\n"; }
}}

# ---- count ----
my $dots=0; for my $r (0..$H-1){for my $c (0..$W-1){ $dots++ if $g[$r][$c] eq '.'||$g[$r][$c] eq 'o'; }}

# ---- autotile + emit ----
print "; back-rendered (after clearing unreachable):\n";
for my $r (0..$H-1) { print ";  ".join('',@{$g[$r]})."\n"; }
print "; dots+pellets=$dots  unreachable=$unreach  asymmetry=$asym\n\n";

my $base = 9101;   # DATA line numbers for maze 2
for my $r (0..$H-1) {
  my $out='';
  for my $c (0..$W-1) {
    my $x=$g[$r][$c];
    if ($x eq '#') { my $m = iswall($r-1,$c)*1 + iswall($r,$c+1)*2 + iswall($r+1,$c)*4 + iswall($r,$c-1)*8;
      if ($m==15) {
        # solid 4-way 'p' fills its corners and pokes into the maze at any open diagonal;
        # emit the thin cross '+' (code 168) there instead. Keep 'p' only as a true wall interior.
        my $poke = ispass($r-1,$c-1)||ispass($r-1,$c+1)||ispass($r+1,$c-1)||ispass($r+1,$c+1);
        $out .= $poke ? '+' : 'p';
      } else { $out .= chr(ord('a')+$m); } }
    elsif ($x eq 'o') { $out .= 'O'; }
    elsif ($x eq '.') { $out .= '.'; }
    elsif ($x eq 'D') { $out .= 'D'; }
    else { $out .= ' '; }
  }
  printf "%d DATA \"%s\"\n", $base + $r, $out;
}
