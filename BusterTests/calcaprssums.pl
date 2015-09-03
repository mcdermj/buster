#!/usr/bin/perl

while(<STDIN>) {
	my $crc = 0xFFFF;

	chomp;
	chop;

	for(my $j = 0; $j < length $_; ++$j) {
		my $ch = ord(substr($_, $j, 1)) & 0xFF;
		for(my $i = 0; $i < 8; ++$i) {
			my $xorflag = ((($crc ^ $ch) & 0x01) == 0x01);
			$crc >>= 1;
			if($xorflag) {
				$crc ^= 0x8408;
			}
			$ch >>= 1;
		}
	}
	$crc = (~$crc) & 0xFFFF;
	printf "\$CRC%04X,%s\n", $crc, $_;
}
