#!/usr/bin/perl -w
while(<>){
   chomp;
   s/\/$//;
   $ri=rindex($_,"/");
   print substr($_, 0, $ri) . "\n";
}
