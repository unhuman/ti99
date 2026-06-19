use strict; use warnings;
my ($src,$idx,$enr,$tun)=@ARGV;
open my $fh,'<',$src or die; my @raw=<$fh>; close $fh; chomp @raw;
my @g = grep { /^[|._-]/ } @raw; die "want 31 got ".scalar(@g) unless @g==31;
sub conv { my $s=shift; $s=~tr/|_/##/; $s=~s/-/D/g; return $s; }
my @ix=split/,/,$idx; die "want 22 got ".scalar(@ix) unless @ix==22;
my @out = map { conv($g[$_-1]) } @ix;
# carve the fixed pen box into grid rows 9-12 (cols 10-19, 1-based = idx 9..18)
my @pen=("          "," ###DD### "," #      # "," ######## ");
for my $k (0..3){ my @c=split//,$out[8+$k]; my @p=split//,$pen[$k]; $c[9+$_]=$p[$_] for (0..9); $out[8+$k]=join('',@c); }
# tunnels: blank 3 outer cells each side
for my $r (split/,/,$tun){ next unless $r; my @c=split//,$out[$r-1]; $c[$_]=' ' for(0,1,2,25,26,27); $out[$r-1]=join('',@c); }
# energizers col2 & col27
for my $r (split/,/,$enr){ next unless $r; my @c=split//,$out[$r-1]; $c[1]='o'; $c[26]='o'; $out[$r-1]=join('',@c); }
print "$_\n" for @out;
