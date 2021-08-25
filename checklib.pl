#!/usr/bin/perl -w
open (LIB, "<libs/lib_rev1_0.spi") || die "Cannot open library file\n";
while (<LIB>){
   chomp;
   /^\s*.subckt\s+/i && do {
      s/^\s+//;
      s/\s+/ /g;
      ($sub, $name, $ports) = split(/ /, $_, 3);
      print "  ... subckt defined: $name\n";
      $Subs{$name}=$ports;
      $Unused{$name}=1;
   };
}
close LIB;

open (SPI, "<digital_top.spi") || die "Cannot open spi file\n";
while (<SPI>){
   chomp;
   s/^\s+//;
   s/\s+/ /g;
   s/^\+\s+// && do {
      #print "... continue line $.: $_\n";
      #print "  ...current line is $#lines\n";
      #print "     last line = $lines[-1]\n";
      $lines[-1] .= " " . $_;
      #print "     new last line = $lines[-1]\n";
      next;
   };
   push @lines, $_;
}
close SPI;

for $_ (@lines) {
   /^\s*.subckt\s+/i && do {
      ($sub, $name, $ports) = split(/ /, $_, 3);
      print "  ... subckt defined: $name\n";
      $Subs{$name}=$ports;
      $Unused{$name}=1;
   };

   /^\s*X(\S+)\s+/ && do {
      ($call, $pinstring) = split(/ /, $_, 2);
      @pins = split(/ /, $pinstring);
      $subckt = pop @pins;
      print "Circuit $call used subckt $subckt\n";
      if (!exists($Subs{$subckt})){
         die "No subckt definition for subckt $subckt\n";
      }
      if (exists($Unused{$subckt})){
         delete $Unused{$subckt};
      }
      
   };
}

for my $cell (sort keys %Unused){
   print "Cell $cell is not used!\n";
}
