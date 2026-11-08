#!/usr/bin/env perl
# conventions-pointers.pl <file>... — every pointer into CONVENTIONS.md or a
# conventions/<topic>.md detail file, one per line: <file>\t<target>\t<quoted heading>,
# or <target>\t!<the text after the arrow> when the pointer quotes no heading.
# Wrapped lines, `#` comment wraps and \" escapes are flattened first.
use strict; use warnings;
for my $f (@ARGV) {
  open(my $fh, '<', $f) or next; local $/; my $t = <$fh>; close $fh;
  next if $t =~ /\x00/;
  $t =~ s/\n[ \t]*#+[ \t]?/ /g if $f =~ /\.(sh|pl|ya?ml)$/;
  $t =~ s/\\"/"/g;
  $t =~ s/\s+/ /g;
  while ($t =~ /((?:\$AB_CONVENTIONS(?:_DIR\/[a-z-]+\.md)?)|(?:conventions\/[a-z-]+\.md)|(?:CONVENTIONS\.md))[`'\]]*(?:\([^)\s]*\))?[`'\]]*(?:'s)? ?(?:→|->) ?/g) {
    my $target = $1; my $rest = substr($t, pos($t), 160);
    $target =~ s/^\$AB_CONVENTIONS_DIR\//conventions\//; $target =~ s/^\$AB_CONVENTIONS$/CONVENTIONS.md/;
    if ($rest =~ /^"([^"]+)"/) { print "$f\t$target\t$1\n"; }
    else { (my $p = $rest) =~ s/^(.{0,50}).*/$1/; print "$f\t$target\t!$p\n"; }
  }
}
