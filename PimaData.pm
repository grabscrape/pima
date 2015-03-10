

package PimaData;
use strict;
use DBI qw(:sql_types);

BEGIN { eval 'use Data::Dumper' if $::_dumper; }

my $dbname='pima';
my $host='localhost';
my $user='pima';
my $password='pIm7a';


my $dbh; 

our $_data;
BEGIN {
  $_data = { 
   tables    => [ qw/ assessor_scrape_%d
                      assessor_scrape_valuation_%d
                      assessor_scrape_recording_%d
                      assessor_scrape_estimate_%d  / ]

   ,base_fields => [ 
      "book_map_parcel VARCHAR(64) PRIMARY KEY, native_parcel VARCHAR(100)"
     ,"book_map_parcel VARCHAR(64) REFERENCES assessor_scrape_%d"
     ,"book_map_parcel VARCHAR(64) REFERENCES assessor_scrape_%d"
     ,"book_map_parcel VARCHAR(64) REFERENCES assessor_scrape_%d" ]

    # for field list
   ,fields => {}
   ,verbose_letters=>[undef,'v','r','e']
  }; 

}

sub db_prepare {
  $dbh = DBI->connect("DBI:mysql:$dbname:$host", $user, $password );
  my $sth;

  my ($table,$base_field);
  foreach my $t ( 0..$#{ $_data->{tables} } ) {
    $table      = sprintf $_data->{tables}->[$t],      $::_version;
    $base_field = sprintf $_data->{base_fields}->[$t], $::_version;


    $sth = $dbh->prepare( 
       "CREATE TABLE IF NOT EXISTS $table ( $base_field )" );

    $sth->execute;
    
  }

  # for speedup
  $sth = $dbh->prepare( 
    "CREATE TABLE IF NOT EXISTS streets_$::_version (
      street_name VARCHAR(64) PRIMARY KEY
      ,completed   INT( 1 ) )"  );
  $sth->execute;

  ### build field list
  foreach my $table ( @{ $_data->{tables} } ) {
    $table   = sprintf $table,    $::_version;
    $_data->{fields}->{$table} = getFieldsList( $table );
  }

}

sub getFieldsList {
  my $t =shift;
  my $sth  = $dbh->prepare("show columns from $t");
  $sth->execute;

  my @a; # field names
  while (my $data = $sth->fetch ) {
    push @a, $data->[0];
  }
  return \@a;
}

sub storeData {
  my $table = shift;
  my $data  = shift;

  #$table .= $::_version;

  if( ( my $t = ref $data) eq 'HASH' ) {
    elementaryStore( $table, $data ); 
  } elsif( $t eq 'ARRAY' ) {
    foreach my $d ( @{ $data } ) {
      elementaryStore( $table, $d ); 
    }
  } else {
    die "error when store";
  }
}

sub elementaryStore {
  my $table = shift;
  my $data  = shift;

  my @fields = sort keys %{ $data };

  addDetailFields( $table, \@fields );

  my $cols_str  = join ',', @fields;
  my $vals_str .= join ',', map { $dbh->quote($data->{$_})} @fields;
  my $q = "INSERT INTO $table ($cols_str) ".
          " VALUES ($vals_str)";

  my $sth = $dbh->prepare( $q ) or die $q;
  $sth->execute or warn "Q=$q\n";

}

sub addDetailFields {
  my $table = shift;
  my $ef_p  = shift;

  my ($sth, $q);
  foreach my $f ( @{ $ef_p } ) {
    if( ! grep $_ eq $f, @{ $_data->{fields}->{$table} } ) {
      $q = "\nALTER TABLE $table ADD COLUMN $f VARCHAR(512)\n";
      $sth = $dbh->prepare( $q );
      $sth->execute or die "\n\nErr: $q\n\n";
      push @{ $_data->{fields}->{$table} }, $f;
    }
  }

}
sub complete_street {
  my $street_name = shift;
  my $num         = shift;
  my $sth;
  $sth = $dbh->prepare(
     "UPDATE streets_$::_version SET completed=$num WHERE street_name=".
        $dbh->quote($street_name) );
  $sth->execute;

  print  STDERR "Street $street_name Completed\n";
}

sub is_street_completed {
  my $street_name = shift;
  my $sth;

  $sth = $dbh->prepare( 
    "SELECT street_name, completed FROM streets_$::_version
      WHERE street_name =". $dbh->quote($street_name ) );
  $sth->execute;

  my @a;
  my( $name, $completed ) = @{ $a } if ($a = $sth->fetch );

  unless( $name ) {

    $sth = $dbh->prepare("INSERT INTO streets_$::_version (street_name) ".
     'VALUES ('. $dbh->quote( $street_name ) . ')' );
    $sth->execute;
    return 0;
  }
  return $completed; # if $completed;
 
}

sub is_parcel_scraped {   


  my $p=shift;
  my $q = "SELECT native_parcel FROM assessor_scrape_$::_version 
           where native_parcel = '$p'";
  my $sth = $dbh->prepare( $q );
  $sth->execute;
  return 1 if $sth->fetch;
  return 0;
}
1;
