package Font::TTF::Morx;

use strict;
use vars qw(@ISA);
use Font::TTF::AATutils;
use Data::Dumper;
require Font::TTF::Table;

@ISA = qw(Font::TTF::Table);


sub read
{
    my ($self) = shift;
    my ($fh, $dat);

    my $cmap = $self->{' PARENT'}->{'cmap'};
    $cmap->read;

    $self->SUPER::read || return $self;
    $fh = $self->{' INFILE'};

    my $header = {};

    $fh->read($dat, 8);	# header
    ($header->{'version'},
     $header->{'flags'},
     $header->{'nChains'}) = unpack('nnN', $dat);

    $header->{'chains'} = [];
    for my $i(0..$header->{'nChains'}-1){
        my $chain = {};
        $fh->read($dat, 16);
        ($chain->{'defaultFlags'},
         $chain->{'chainLength'},
         $chain->{'nFeatureEntries'},
         $chain->{'nSubtables'}) = unpack('NNNN', $dat);

        push @{$header->{'chains'}}, $chain;

        $chain->{'features'} = [];
        for my $j(1..$chain->{'nFeatureEntries'}){
            my $feature = {};
            $fh->read($dat, 12);
            ($feature->{'featureType'},
             $feature->{'featureSetting'},
             $feature->{'enableFlags'},
             $feature->{'disableFlags'}) = unpack('nnNN', $dat);
            push @{$chain->{'features'}}, $feature;
        }

        $chain->{'subtables'} = [];
        for my $j(1..$chain->{'nSubtables'}){
            my $subtable = {};
            $fh->read($dat, 12);
            ($subtable->{'length'},
             $subtable->{'coverage'},
             $subtable->{'subFeatureFlags'}) = unpack('NNN', $dat);
            $subtable->{'type'} = 0xFF & $subtable->{'coverage'};

            my $cursor = $fh->tell() + $subtable->{'length'} - 12;

            if ($subtable->{'type'} == 1){ $self->read_contextual_subs($subtable, $fh, $cursor); }
            if ($subtable->{'type'} == 2){ $self->read_ligatures($subtable, $fh, $cursor); }

            push @{$chain->{'subtables'}}, $subtable;
            $fh->seek($cursor, 0);
        }
    }

    $self->{'header'} = $header;

    $self;
}

sub read_ligatures
{
	my ($self, $subtable, $fh, $endOffset) = @_;

	my $dat;
	my $start = $fh->tell();

	$fh->read($dat, 7 * 4);

	my $header = {};
	($header->{'nClasses'},
	 $header->{'classTableOffset'},
	 $header->{'stateArrayOffset'},
	 $header->{'entryTableOffset'},
	 $header->{'ligActionOffset'},
	 $header->{'componentOffset'},
	 $header->{'ligatureOffset'}) = unpack('NNNNNNN', $dat);
	$subtable->{'header'} = $header;

	# we'll read the 6 tables, which we can later use to walk
	# and build the actual map
	my $tables = {};

	# read class table
	my $len = $header->{'stateArrayOffset'} - $header->{'classTableOffset'};
	$fh->seek($start + $header->{'classTableOffset'}, 0);
	my ($classFormat, $classLookup) = Font::TTF::AATutils::AAT_read_lookup($fh, 2, $len, 0);
	$tables->{'classTable'} = $classLookup;

	# read state array
	my $len = $header->{'entryTableOffset'} - $header->{'stateArrayOffset'};
	$fh->seek($start + $header->{'stateArrayOffset'}, 0);
	my $nStates = $len / (2 * $header->{'nClasses'});
	$tables->{'stateArray'} = [];
	for my $i(1..$nStates){
		$fh->read($dat, $header->{'nClasses'} * 2);
		push @{$tables->{'stateArray'}}, [unpack('n*', $dat)];
	}

	# read entry table
	my $len = $header->{'ligActionOffset'} - $header->{'entryTableOffset'};
	$fh->seek($start + $header->{'entryTableOffset'}, 0);
	my $entries = $len / 6;
	$tables->{'entryTable'} = [];
	for my $i(1..$entries){
		$fh->read($dat, 6);
		push @{$tables->{'entryTable'}}, [unpack('nnn', $dat)];
	}

	# read lig action
	my $len = $header->{'componentOffset'} - $header->{'ligActionOffset'};
	$fh->seek($start + $header->{'ligActionOffset'}, 0);
	$fh->read($dat, $len);
	$tables->{'ligActions'} = [unpack('N*', $dat)];

	# read component
	my $len = $header->{'ligatureOffset'} - $header->{'componentOffset'};
	$fh->seek($start + $header->{'componentOffset'}, 0);
	$fh->read($dat, $len);
	$tables->{'components'} = [unpack('n*', $dat)];

	# read ligature
	my $len = $endOffset - $header->{'ligatureOffset'};
	$fh->seek($start + $header->{'ligatureOffset'}, 0);
	$fh->read($dat, $len);
	$tables->{'ligatures'} = [unpack('n*', $dat)];

	$subtable->{'tables'} = $tables;
}

sub read_contextual_subs
{
	my ($self, $subtable, $fh, $endOffset) = @_;

	my $dat;
	my $start = $fh->tell();

	$fh->read($dat, 5 * 4);

	my $header = {};
	($header->{'nClasses'},
	 $header->{'classTableOffset'},
	 $header->{'stateArrayOffset'},
	 $header->{'entryTableOffset'},
	 $header->{'substitutionTable'}) = unpack('NNNNN', $dat);
	$subtable->{'header'} = $header;


	# we'll read the 4 tables, which we can later use to walk
	# and resolve replacements
	my $tables = {};

	# read class table
	my $len = $header->{'stateArrayOffset'} - $header->{'classTableOffset'};
	$fh->seek($start + $header->{'classTableOffset'}, 0);
	my ($classFormat, $classLookup) = Font::TTF::AATutils::AAT_read_lookup($fh, 2, $len, 0);
	$tables->{'classTable'} = $classLookup;
	$tables->{'classFormat'} = $classFormat;

	# read state array
	my $len = $header->{'entryTableOffset'} - $header->{'stateArrayOffset'};
	$fh->seek($start + $header->{'stateArrayOffset'}, 0);
	my $nStates = $len / (2 * $header->{'nClasses'});
	$tables->{'stateArray'} = [];
	for my $i(1..$nStates){
		$fh->read($dat, $header->{'nClasses'} * 2);
		push @{$tables->{'stateArray'}}, [unpack('n*', $dat)];
	}

	# read entry table
	my $len = $header->{'substitutionTable'} - $header->{'entryTableOffset'};
	$fh->seek($start + $header->{'entryTableOffset'}, 0);
	my $entries = $len / 8;
	$tables->{'entryTable'} = [];
	for my $i(1..$entries){
		$fh->read($dat, 8);
		push @{$tables->{'entryTable'}}, [unpack('nnnn', $dat)];
	}

	# figure out how many lookup tables we have
	my $len = $endOffset - $header->{'substitutionTable'};

	$fh->seek($start + $header->{'substitutionTable'}, 0);
	$fh->read($dat, 4);
	my ($firstOffset) = unpack('N', $dat);
	my $lookupTables = $firstOffset / 4;

	# get the offset for each table
	$fh->seek($start + $header->{'substitutionTable'}, 0);
	$fh->read($dat, 4*$lookupTables);
	$tables->{'lookupOffsets'} = [unpack('N*', $dat)];

	my $end_offset = $len - (4*$lookupTables);

	# read each lookup table
	$tables->{'lookupTables'} = [];
	for my $i(0..$lookupTables-1){
		my $tbl_start = $tables->{'lookupOffsets'}->[$i];
		my $tbl_end = $i == $lookupTables-1 ? $end_offset : $tables->{'lookupOffsets'}->[$i+1];
		my $tbl_len = $tbl_end - $tbl_start;

		#print "loading lookup table $i, from $tbl_start to $tbl_end\n";

		$fh->seek($start + $header->{'substitutionTable'} + $tbl_start, 0);
		my ($subFormat, $subLookup) = Font::TTF::AATutils::AAT_read_lookup($fh, 2, $tbl_len, 0);

		$tables->{'lookupTables'}->[$i] = $subLookup;
	}

	$subtable->{'tables'} = $tables;
}

sub resolve_ligature {
	my ($self, $cps) = @_;


	# first, turn cp list into glyph list

	my $cmap = $self->{' PARENT'}->{'cmap'};

	my $glyphs = [];
	for my $cp (@{$cps}){
		my $index = $cmap->{'Tables'}[0]{'val'}->{$cp};
		if (!$index){ return 0; }
		push @{$glyphs}, $index;
	}
	


	# now, loop over each chain, applying transforms

	for my $chain_id(0..scalar(@{$self->{'header'}->{'chains'}})-1){
		#print "scanning chain ${chain_id}...\n";

		for my $subtable_id(0..scalar(@{$self->{'header'}->{'chains'}->[$chain_id]->{'subtables'}})-1){

			#print "  scanning subtable ${subtable_id}...\n";

			my $ret = $self->resolve_ligature_table($glyphs, $self->{'header'}->{'chains'}->[$chain_id]->{'subtables'}->[$subtable_id]);
			return $ret if $ret;

			my $ret = $self->resolve_contextual_table($glyphs, $self->{'header'}->{'chains'}->[$chain_id]->{'subtables'}->[$subtable_id]);
			return $ret if scalar @{$ret};
		}
	}

	return 0;
}

sub resolve_ligature_table {
	my ($self, $glyphs, $table) = @_;

	#
	# only resolve from ligature subtables, not swashes, etc.
	#

	if ($table->{'type'} != 2){
		#print "not a lig table (type=$table->{'type'}, length=$table->{'length'})\n";
		return 0;
	}

	#
	# we reverse the glyphs into a stack, with classes.
	# start with $state of 1. if we get back to state 0 or 1 then give up.
	#

	my $stack = [];
	for my $index (@{$glyphs}){
		my $class = $table->{'tables'}->{'classTable'}->{$index};

		if (!$class){ return 0; }

		unshift @{$stack}, [$index, $class];
	}

	my $proc_stack = [];
	my $state = 1;


	#
	# now loop
	#

	while (scalar(@{$stack})){

		my ($next, $class) = @{pop @{$stack}};
		my $entry = $table->{'tables'}->{'stateArray'}->[$state]->[$class];

		#print "state $state: idx $next, cls $class, ent $entry\n";

		my ($next_state, $flags, $action) = @{$table->{'tables'}->{'entryTable'}->[$entry]};

		#printf "\tflags: %x\n", $flags;

		if ($flags & 0x8000){
			push @{$proc_stack}, $next;
		}
		if ($flags & 0x4000){
			push @{$stack}, [$next, $class];
		}
		if ($flags & 0x2000){
			#print "running lig action $action!\n";

			my $acc = 0;

			while (scalar(@{$proc_stack})){

				my $idx = pop @{$proc_stack};
				my $action_val = $table->{'tables'}->{'ligActions'}->[$action];

				#print "processing idx $idx with action value $action_val\n";

				my $offset = $self->sign_extend_30($action_val & 0x3FFFFFFF);
				#print "num = $offset\n";

				my $component = $idx + $offset;
				my $component_value = $table->{'tables'}->{'components'}->[$component];

				#print "component $component, value $component_value\n";
				$acc += $component_value;
				$action++;

				if ($action_val & 0x40000000 || $action_val & 0x80000000){
					#print "store!\n";

					my $glyph = $table->{'tables'}->{'ligatures'}->[$acc];

					#print "accum $acc -> glyph $glyph\n";
					#print "\n";

					#print Dumper $table->{'tables'}->{'ligatures'};

					return $glyph;
				}
			}

			#print Dumper $table->{'tables'}->{'ligActions'};
			return 0;
		}

		$state = $next_state;
		if ($state == 0 || $state == 1){
			return 0;
		}
	}

	return 0;
}

sub resolve_contextual_table {
	my ($self, $glyphs, $table) = @_;

	#
	# only resolve from contextual subtables, not swashes, etc.
	#

	if ($table->{'type'} != 1){
		#print "not a contextual table (type=$table->{'type'}, length=$table->{'length'})\n";
		return [];
	}


	#
	# we reverse the glyphs into a stack.
	# start with $state of 1. if we get back to state 0 or 1 then give up.
	#
#print "trying to map stack...\n";
	my $stack = [];
	for my $index (@{$glyphs}){
		my $class = $table->{'tables'}->{'classTable'}->{$index};

		if (!$class){ return []; }

		unshift @{$stack}, [$index, $class];
	}
#print Dumper $stack;
#exit;
	my $state = 1;
	my $mark = [];
	my $out_stack = [];


	#
	# now loop
	#

	while (scalar(@{$stack})){

		my ($next, $class) = @{pop @{$stack}};
		my $entry = $table->{'tables'}->{'stateArray'}->[$state]->[$class];

		#print "state $state: idx $next, cls $class, ent $entry\n";

		my ($next_state, $flags, $markIndex, $currentIndex) = @{$table->{'tables'}->{'entryTable'}->[$entry]};

		#printf "\tnext: %d, flags: %04x, mark: %d, current: %d\n", $next_state, $flags, $markIndex, $currentIndex;

		if ($markIndex != 0xffff){
			my $replace = $table->{'tables'}->{'lookupTables'}->[$markIndex]->{$mark->[0]};
			push @{$out_stack}, $replace;

			#print "\treplace mark ($mark->[0]/$mark->[1]) from table $markIndex\n";
			#print "\t\treplacement is $replace\n";
		}

		if ($currentIndex != 0xffff){
			my $replace = $table->{'tables'}->{'lookupTables'}->[$currentIndex]->{$next};
			push @{$out_stack}, $replace;

			#print "\treplace current ($next/$class) from table $currentIndex\n";
			#print "\t\treplacement is $replace\n";
		}


		if ($flags & 0x8000){
			#print "SET MARK\n";
			$mark = [$next, $class];
		}
		if ($flags & 0x4000){
			#print "don't advance\n";
			push @{$stack}, [$next, $class];
		}

		$state = $next_state;
	}

	if (scalar @{$out_stack}){
		return $out_stack;
	}

	#print "exited - stack empty\n";
	return [];
}

sub sign_extend_30 {
	my ($self, $num) = @_;

	my $last = 0x20000000 & $num;
	if ($last){
		$num = $num | 0xC0000000;
	}

	$num = unpack('l', pack('L', $num));

	return $num;
}


1;
