#!/usr/bin/perl


package PimaHandlers;
use strict;
BEGIN {
  eval ("use Data::Dumper") if $::_dumper;
}

# id == 5;
sub book_map_handler {
  my $p   = shift;
  my $num = shift;
  my %hash;


  foreach my $a ( @{ $p->[0] } ) {
    my( $k,$v ) = split /:\s*/, $a;
    next if $k =~ m/^Oblique I/;
    $hash{normalize_key($k) } = $v;
  }
  return  \%hash ;
}

sub address_handler {  
  my $p   = shift;
  my $num = shift;
  my %hash;
  my $lines=0;
  my $prefix='address__';
  shift @{ $p }; 
  
  my $keys = shift @{ $p };
  foreach my $a ( @{ $p } ) {
    $lines++;
    foreach my $i ( 0.. $#{ $keys } ) {
      my $k = $prefix.normalize_key( $keys->[$i] );
      $hash{ $k } .= '; ' if $hash{ $k };
      $hash{ $k } .= $a->[$i];
    }
  }
  # how many address lines
  $hash{substr($prefix,0,(length $prefix) -1).'lines'} = $lines;

  return \%hash;

}
sub taxpayer_info {
  my $p   = shift;
  my $num = shift;
  my $key = normalize_key( (shift @{ $p })->[0] );
  my @ret;
  foreach my $elem ( @{ $p } ) {
    next if scalar @{ $elem } ==1 and $elem->[0] eq '';
    push @ret,  join ', ', @{ $elem };
  }
  
  return { $key => join '; ', @ret };
}


sub property_descr {
  my $p   = shift;
  my $num = shift;

  # cut first elem
  shift @{ $_ } for  @{ $p };

  my $key = normalize_key( (shift @{ $p })->[0] );
  my @ret;
  foreach my $elem ( @{ $p } ) {
    next if scalar @{ $elem } ==0;
    next if scalar @{ $elem } ==1 and $elem->[0] eq '';
    push @ret,  join ', ', @{ $elem };
  }
 
  return { $key => join '; ', @ret };
  
}
sub valuation_data {
  my $p      = shift;
  my $num    = shift;
  my $data   = shift;

  my ($k,$key);
  my %hash;
  my $parcel = $data->{"assessor_scrape_$::_version"}->{'book_map_parcel'};

  for( my $i=3; $i<=$#{$p}; $i++ ) {
    $k=$p->[$i]->[0]; 
    foreach my $col ( 1..$#{ $p->[2] } ) {
      $key = $k.'__'.$p->[2]->[$col];
      $key = normalize_key( $key );
      $hash{$p->[1]->[$col]}->{$key} = $p->[$i]->[$col];
      $hash{$p->[1]->[$col]}->{year} = $p->[1]->[$col];
      $hash{$p->[1]->[$col]}->{book_map_parcel} = $parcel;
    }
  }

  my @ret;
  push @ret, $hash{$_} for keys %hash;
  return \@ret;
}
sub property_info {
  my $p   = shift;
  my $num = shift;
  my $key = normalize_key( (shift @{ $p })->[0] );
  my ($k,%hash);
  foreach my $item ( @{ $p } ) {
    $k= normalize_key( $item->[0] );
    $hash{'property_info__'.$k} = $item->[1] if $item->[1];
  }
  return \%hash;
}
sub valuation_area {
  my $p   = shift;
  my $num = shift;
  shift @{ $p };
  my %hash;

  map { $hash{'valuation_area__'.normalize_key($_->[0])}=$_->[1] } @{$p};
  return \%hash;

}

sub recording_info {
  my $p   = shift;
  my $num = shift;
  my $data   = shift;
  my $parcel = $data->{"assessor_scrape_$::_version"}->{'book_map_parcel'};


  shift @{ $p };
  my @keys = @{ shift @{ $p } };
  my @ret;

  foreach my $item ( @{ $p } ) {
    my $tmp={};
    foreach my $i ( 0..$#keys ) {
      $tmp->{normalize_key($keys[$i])} = $item->[$i] if $item->[$i];
    }
    $tmp->{book_map_parcel} = $parcel;
    push @ret, $tmp;
  }
  return \@ret;
}

sub commercial_char {
  my $p   = shift;
  my $num = shift;
  shift @{ $p };

  my $prefix='commercial_characteristics__';

  my %hash = map{ $prefix.normalize_key($p->[0]->[$_] )
       => $p->[1]->[$_] }  (0.. $#{$p->[0]} );

  return \%hash;
}

sub sales_info {
  my $p   = shift;
  my $num = shift;
  my $prefix = 'sales_info__';
  my $key = normalize_key( (shift @{ $p })->[0] );
  my @cols = @{ shift @{ $p } };
  my (%hash,$k,$cnt);

  #print STDERR "Number: ", $#{$p}, Dumper $p;

  for( my $e=0; $e< $#{ $p }; $e++ ) {
    foreach my $c ( 0..$#cols ) {
      $k = normalize_key($prefix.$cols[$c]);
      $hash{$k} .= '; '
      if $hash{$k};
      $hash{$k} .= $p->[$e]->[$c];
    }
#    if(  $p->[$e+1]->[0] =~ m/^DEED:/ ) {
      $k = normalize_key($prefix.'deed');
      $hash{$k} .= '; ' if $hash{$k};
      if( (my $a=$p->[$e+1]->[0] ) ) {
	$hash{$k} .= $a;
      } else {  
	$hash{$k} .= 'NOT SPECIFIED';
      }
      $e++;
#    }
    $cnt++;
  }
  $hash{substr($prefix,0,(length $prefix) -1).'lines'}=$cnt;
  #print STDERR Dumper \%hash;
  return \%hash;
}

sub mobile_home {
  my $p   = shift;

  shift @{ $p };
  my $prefix='mobile_home__';
  my %hash = map{ $prefix.normalize_key($p->[0]->[$_] )
       => $p->[1]->[$_] }  (0.. $#{$p->[0]} );

  return \%hash;
}

sub  residential_char {
  my $p   = shift;
  shift @{ $p };
  my $prefix='residential_characteristics__';
  my $appraiser;
  my %hash;
  if( $p->[0]->[0] =~ m/Property\s+Appraiser:\s*(.*)$/s ) {
   $appraiser =$1;
   $appraiser =~ s/\s+\n\s+/; /s; 
   $hash{$prefix.'appraiser'} = $appraiser;
   shift @{ $p };
  } else {
   warn "Undiscovered resid.char. situation found: ", $p->[0]->[0];
  }
  my $k;
  foreach my $twice ( @{ $p } ) {
    for( my $i=0; $i<$#{$twice}; $i +=2 ) {
      $k=$prefix.normalize_key($twice->[$i]);
      $hash{$k} = $twice->[$i+1] if $twice->[$i] and $twice->[$i+1];
    }
  }
  return \%hash;
}
sub guesthouse {
  my $p = shift;
  shift @{ $p };
  my $prefix='guesthouse__';
  my ($k,%hash);

  foreach my $twice ( @{ $p } ) {
    for( my $i=0; $i<$#{$twice}; $i +=2 ) {
      $k=$prefix.normalize_key($twice->[$i]);
      $hash{$k} = $twice->[$i+1] if $twice->[$i] and $twice->[$i+1];
    }
  }
  return \%hash;
}
sub owners_estimate {
  my $p  = shift;
  my $id = shift;
  my $data   = shift;

  my $parcel = $data->{"assessor_scrape_$::_version"}->{'book_map_parcel'};

  shift @{ $p };
  my @ret;
  my @cols = @{ shift @{ $p } };
  @cols = map { normalize_key($_) } @cols;
  foreach my $elem ( @{ $p } ) {
    my $tmp = {};
    for( my $i=0; $i<=$#cols; $i++ ) {
      $tmp->{$cols[$i]}=$elem->[$i];
    }
    $tmp->{book_map_parcel} = $parcel;
    push @ret, $tmp;
  }
  return \@ret;
}


sub additional_items {
  my $p = shift;
  my %hash;
  my $lines=0;
  my $prefix='additional_items__';

  shift @{ $p };

  my $keys = shift @{ $p };
  foreach my $a ( @{ $p } ) {
    $lines++;
    foreach my $i ( 0..$#{ $keys } ) {
      my $k = $prefix.normalize_key($keys->[$i] );
      $hash{$k} .= '; ' if $hash{$k};
      $hash{$k} .= $a->[$i];
    }
  }

  $hash{substr($prefix,0,(length $prefix) -1).'lines'} = $lines;
  return \%hash;
}
sub parcel_note {
  my $p = shift;
  shift @{ $p };
  my $prefix = 'parcel_note';
  return { $prefix=>join(';',@{ $p->[0]} ) };
}

sub obsolescence {
  my $p = shift;
  shift @{$p};
  my $r;
  foreach my $a ( @{ $p } ) {
    for( my $i=0; $i<$#{ $a }; $i+=2 ) {
      $r .= '; ' if $r;
      $r .= $a->[$i];
    }
  }
  return { 'obsolescence'=>$r };
}


#  For example for:
#  frm_Parcel.aspx?parcel=11703164D&taxyear=2010
sub enhancement {
  my $p = shift;
  shift @{ $p };
  my %hash;
  my @cols = @{ shift @{ $p } };
  @cols = map { 'enhancement_'.normalize_key($_) } @cols;
  foreach my $e ( @{ $p } ) {
    for( my $i=0;$i<=$#cols;$i++) {
      $hash{$cols[$i]} = $e->[$i]||undef; # if $cols[$i] and $e->[$i];
    }
  }
  return \%hash;
}

sub empty {
}


sub normalize_key {
  my $k = shift;
  my $prefix = shift;
  $k =~ s/(-|\s)/_/g;
  $k =~ s/:$//;
  $k =~ s/\.$//;
  $k =~ s/\._/_/;
  $k =~ s/\&/and/;
  $k =~ s/\//_/;
  return $prefix.(lc $k);
}

1;
