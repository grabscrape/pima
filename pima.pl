#!/usr/bin/perl

use strict;
use Pod::Usage;
use Getopt::Long;
use IO::Handle;
STDERR->autoflush(1);
STDOUT->autoflush(1);

our ($_dumper,$_emulate,$_verbose);
BEGIN { $_dumper =1; $_emulate =0; $_verbose=2; }

require PimaData;

our  $_version =        2; 
my  ($_help,$_man);

GetOptions('version=i'=>\$_version,
           'verbose=i'=>\$_verbose,
           'help|?'   =>\$_help,
           'man'      =>\$_man) or pod2usage(2);

pod2usage(1) if $_help;
pod2usage(-exitstatus => 0, -verbose => 2) if $_man;

die "Incorrect value for '-verbose' option." 
       unless( $_verbose == 1 or $_verbose == 2 );

&PimaData::db_prepare;
&GoWWW::get_and_save;

package GoWWW;
use strict;

use HTML::TableParser;
use WWW::Mechanize;
my ($pima,$pima_street,$start_page);

BEGIN {
  eval 'use Data::Dumper' if $::_dumper;
  require PimaHandlers;

  $start_page = 'http://www.asr.pima.gov/links/frm_AdvancedSearch_v2.aspx?search=Parcel';
#  $start_page = 'http://d7.dp.ua/Page.html' if $::_emulate;

  $pima        = WWW::Mechanize->new( noproxy=>0 ); # 1 - no proxy
  $pima_street = WWW::Mechanize->new( noproxy=>0 ); # 1 - no proxy

  unless ( $::_emulate ) {
    $pima->get( $start_page );
    $pima_street->get( $start_page );
  }

}

sub street_letter {
  return [ 1 ] if $::_emulate;
  return $pima_street->find_all_links(
               url_regex => qr[^frm_StreetIndex\.aspx\?selected] );
}


sub get_and_save {

  my $url;
  my ($tmp,$parcel_num,$parcel_url_links_ptr);

  # every letter;
  foreach my $a ( &street_letter ) {

    my $tmp;
    if( $::_emulate ) {
      my $content = `cat Streets1.html`;
      $tmp = \$content;
    } else {
      $url = $a->[0];
      #$url = 'Streets.html' if $::_emulate;
      $pima_street->get( $url );
      $tmp = \$pima_street->content;
    }

    my $letter = $a->[0];
    $letter =~ s/.*=(.*)$/$1/;

    print STDERR "Letter '$letter':\n";
    my @streets_list  = parseStreetNames( $tmp );
    my $streets_number = scalar @streets_list; 

    # every street
    my $street_cnt;
    foreach my $street ( @streets_list ) {
      $street_cnt++;
      print STDERR "  $street: [$streets_number/$street_cnt] ";

      if( (my $n = &PimaData::is_street_completed(  $street ) ) ) {
        print STDERR "Already scraped [$n]. Skip.\n";
        next;
      }

      print STDERR "\n";


      # every parcel page
      my $parcel_cnt;
      foreach my $page ( getParcelListPage( $street ) ) {
        ($parcel_num,$parcel_url_links_ptr) = parseParcelListPage( $page ) ;


        $parcel_cnt=0;
        foreach my $parcel (  @{ $parcel_url_links_ptr } ) {
          $parcel_cnt++;
          #last if $parcel_cnt > 4 and (  1 || $_emulate );
          # frm_Parcel.aspx?parcel=117031650&taxyear=2010
          my $native_parcel; # inner parcel no.
          printf STDERR "    [%d/%d] $parcel ", $parcel_num,$parcel_cnt;

          if( $parcel =~ m/parcel=(.+?)\&/ ) { 
            $native_parcel = $1;
            if( &PimaData::is_parcel_scraped( $native_parcel) ) {
              print STDERR "Skip\n";
              next;
            }
          }

          if( $::_emulate )  {
            my $file = "Emulate/Parcel${parcel}.html";
            $tmp = `cat $file`;
          } else {
RESTART:
            $pima->get( $parcel );
            $tmp = $pima->content;

            while( $tmp =~ m/\b.*>(.*?timeout.*?)<.*\b/ ) {
            #while( $tmp =~ m/\b.*>(.*?timeout.*?)<.*\b/ ) {
              print STDERR "(timeout)"; sleep( 10 );
              $pima->reload;
              $tmp = $pima->content;
            }
          }

          # Fix GuestHouse table errors.
          if( $tmp =~ m/\bGuesthouse\b/ ) {
            #$tmp =~ s/(<!-- \*{7} Guesthouse \*{7} -->\s*)<\/table>/$1/m;
            $tmp =~ s/(<!-- \*{7} Guesthouse \*{7} -->\s*)<\/table>(.+?<\/tr>)(\s*<\/div>)/$1$2<\/table>$3/s;
            $tmp =~ s/colspan=4''/colspan='4'/m;
          }
          # Fix Additional table errors.
          if( $tmp =~ m/\bAdditional\b/ ) {
            #$tmp =~ s/(<!-- \*{7} Additional \*{7} -->\s*)<\/table>/$1/m;
            $tmp =~ s/(<!-- \*{7} Additional \*{7} -->\s*)<\/table>(.+?<\/tr>)(\s*<\/div>)/$1$2<\/table>$3/s;
            #$tmp =~ s/colspan=4''/colspan='4'/m;
          }
          # Caption as '<td>..</td>'
          $tmp =~ s/<caption.*?>/<tr><td>/mg;
          $tmp =~ s/<\/caption>/<\/td><\/tr>/mg;

          $tmp =~ s/<th(.*?)>/<td$1>/mg;
          $tmp =~ s/<\/th>/<\/td>/mg;
 
          if( $tmp =~ m/(Book-Map-Parcel:).*?value="(.+?)"/ ) {
            my $where = $1;
            my $what  = $2;
            $tmp =~ s/$where/$where$what/;
            die "Panic!!! $where $what" unless $what;
          }

          my ( $num, $data ) = parseParcelPage( \$tmp );

          $data->{"assessor_scrape_$::_version"}->{native_parcel} = $native_parcel;
          unless(  $data->{"assessor_scrape_$::_version"}->
                             {book_map_parcel} ) {
            warn "Panic! book_map_parcel not catched. reload page" ;
            $pima->back;
            goto RESTART;
          }     
          my @res;
          foreach my $i ( 0..$#{ $PimaData::_data->{tables} } ) {
            my $table = $PimaData::_data->{tables}->[$i];

	           # @{ $PimaData::_data->{tables} } keys %{ $data } ) {
            next unless $data->{$table};

            &PimaData::storeData( $table, $data->{$table} );


            
            if( (my $t = ref $data->{$table}) eq 'HASH' ) {
	      push @res, scalar keys %{ $data->{$table} };
            } elsif ( $t eq 'ARRAY' ) {

	      my $cnt=0;
	      $cnt += scalar keys %{ $_ } for @{ $data->{$table} };

              push @res, "$cnt".$PimaData::_data->{verbose_letters}->[$i];
            } else {
	      push @res, '0'.$PimaData::_data->{verbose_letters}->[$i];
              #warn "strgange error";
            }
          }
          print STDERR "ok [$num: ",join( ',', @res), ']';
          print STDERR "\n" if $::_verbose == 2;
          $pima->back;
        }
      }

      $pima->back;
      &PimaData::complete_street( $street, $parcel_cnt );
    }
  } # by street
}


my $parcelRawData;
my @parser_reqs;
my $tables_cnt=0;
my @data_structure;
#my $_parser;
my $atom;
BEGIN {
  $atom = { id=>sub{1}
              ,row=>sub { push @{$parcelRawData->[$tables_cnt]}, $_[2] }
              ,end=>sub { $tables_cnt++ } };

  @parser_reqs = ( 
        $atom, $atom, $atom, $atom, $atom, $atom, $atom,
        $atom, $atom, $atom, $atom, $atom, $atom, $atom,
        $atom, $atom, $atom, $atom, $atom, $atom, $atom  );

  @data_structure = (
     { re=>qr/^HOME\s/ }
    ,{ re=>qr/^Parcel Detail$/ }
    ,{ re=>qr/^Summary$/ }
    ,{ re=>qr/^Property Address$/ }
    ,{ re=>qr/^Book-Map-Parcel:/,  hn=>\&PimaHandlers::book_map_handler,
                    depot=>'assessor_scrape_' }
    ,{ re=>qr/^Property Address:$/, hn=>\&PimaHandlers::address_handler,
                    depot=>'assessor_scrape_' }
    ,{ re=>qr/^$/ } #, hn=>\&PimaHandlers::empty }
    ,{ re=>qr/^Taxpayer Information:$/, hn=>\&PimaHandlers::taxpayer_info,
                    depot=>'assessor_scrape_' }
    ,{ re=>qr/^Property\s+Description:$/, hn=>\&PimaHandlers::property_descr,
                    depot=>'assessor_scrape_' }
    ,{ re=>qr/^Valuation\s+Data:$/, hn=>\&PimaHandlers::valuation_data,
                    depot=>'assessor_scrape_valuation_' }
    ,{ re=>qr/^Property\s+Information:$/, hn=>\&PimaHandlers::property_info,
                    depot=>'assessor_scrape_' }
    ,{ re=>qr/^Valuation\s+Area:$/, hn=>\&PimaHandlers::valuation_area,
                    depot=>'assessor_scrape_' }
    ,{ re=>qr/^Recording\s+Information$/, hn=>\&PimaHandlers::recording_info,
                    depot=>'assessor_scrape_recording_' }
    ,{ re=>qr/^Commercial\s+Characteristics:$/, hn=>\&PimaHandlers::commercial_char,
                    depot=>'assessor_scrape_' }
    ,{ re=>qr/^Sales\s+Information:$/, hn=>\&PimaHandlers::sales_info,
                    depot=>'assessor_scrape_' }

    ,{ re=>qr/^Mobile\s+Home:$/, hn=>\&PimaHandlers::mobile_home,
                    depot=>'assessor_scrape_' }

    ,{ re=>qr/^Residential\s+Characteristics:$/, hn=>\&PimaHandlers::residential_char,
                    depot=>'assessor_scrape_' }
    ,{ re=>qr/^Guesthouse:$/, hn=>\&PimaHandlers::guesthouse,
                    depot=>'assessor_scrape_' }
    ,{ re=>qr/^Owner's\s+Estimate:$/, hn=>\&PimaHandlers::owners_estimate,
                    depot=>'assessor_scrape_estimate_' }
    ,{ re=>qr/^Additional\s+Items:$/, hn=>\&PimaHandlers::additional_items,
                    depot=>'assessor_scrape_' }
    ,{ re=>qr/^Parcel\s+Note:$/, hn=>\&PimaHandlers::parcel_note,
                    depot=>'assessor_scrape_' }
    ,{ re=>qr/^Obsolescence:$/, hn=>\&PimaHandlers::obsolescence,
                    depot=>'assessor_scrape_' }
    ,{ re=>qr/^Enhancement:$/, hn=>\&PimaHandlers::enhancement,
                    depot=>'assessor_scrape_' }
  );

}

sub parseParcelPage {
  my $ptr=shift;
  my $id;
  $parcelRawData = undef;


  $id=0;
  $tables_cnt=0;
  my $_parser = HTML::TableParser->new( \@parser_reqs,
               { Decode => 1, Trim => 1, Chomp => 1, DecodeNBSP=>1 } );
  $_parser->parse( $$ptr );

  my $return_hash={};
  foreach my $scope ( @{ $parcelRawData } )  {
    if( (my @handler=grep $scope->[0]->[0] =~ m/$_->{re}/, @data_structure )) {
      if( exists $handler[0]->{hn} ) {
        $id++;
        my $func = $handler[0]->{hn};
        my $data = &$func( $scope, $id, $return_hash );

        if( ( my $t = ref $data ) eq 'HASH' ) {
           map { $return_hash->{($handler[0]->{depot})."$::_version"}->{$_} = $data->{$_} }
                   keys %{ $data };
        } elsif( $t eq 'ARRAY' ) {
           $return_hash->{($handler[0]->{depot})."$::_version"} = $data;
        } else {
          warn "Strange err:",  ($handler[0]->{re}), "\n";
        }
      }
    } else {
      #print STDERR Dumper $return_hash;
      print STDERR "Unexpected tag", Dumper $scope;
      print STDERR "Outed\n";
#return;
    }
  }
#  print STDERR Dumper $return_hash;
  #print  STDERR '[',$id,"] end\n";
  return $id, $return_hash;
}

sub getParcelListPage {
  my $street = shift;

  my $tmp;
  if( $::_emulate ) {
    my $a = `cat parcel-list.html`;
    $tmp = \$a;
  } else {
    $pima->field('ctl00$ContentPlaceHolder1$txtStreetName',$street);
    $pima->click_button( name=>'ctl00$ContentPlaceHolder1$btnPropAdd' );
    $tmp = \$pima->content;
  }
  return $tmp;

}

my @parcelNumbersArray;
sub parseParcelListPage {
  my $ptr = shift;
  my @reqs = ( {id=>'2',row=>\&parcelTableHandler } );
  @parcelNumbersArray = ();
  my $p = HTML::TableParser->new( \@reqs,
              ,{ Decode => 1, Trim => 1, Chomp => 1, DecodeNBSP=>1 } );
  $p->parse( $$ptr );
  my $num = @parcelNumbersArray[3]->[0];
  $num =~ s/\D*(\d+)\D.*/$1/;

  return $num, [ (1,2) ] if $::_emulate;
  return $num, [ (1) ] if $::_emulate;
  return $num, [ map { $_->[0] } 
         $pima->find_all_links ( url_regex => qr/^frm_Parcel\.aspx\?parcel=\d+/ ) ];

}

sub parcelTableHandler {
  my(undef,undef,$cols) =@_;
  push @parcelNumbersArray, $cols;
}


my @streetNamesArray;
sub streetTableHandler {
  my(undef,undef,$cols) =@_;
  push @streetNamesArray, $cols;
}

sub parseStreetNames {

  my $ptr  = shift;
  my @reqs = ( { id=>'1',row=>\&streetTableHandler } );
  @streetNamesArray = ();
  my $p = HTML::TableParser->new( \@reqs
              ,{ Decode => 1, Trim => 1, Chomp => 1, DecodeNBSP=>1 } );

  $p->parse( $$ptr );
  my %tmp;
  $tmp{ $_ } =1 for map { $_->[1] } @streetNamesArray[2..$#streetNamesArray];

  return sort { $a <=> $b } keys %tmp;
  #return sort keys %tmp;

}

=head1 NAME

pima.pl - the scrapper for 'www.asr.pima.gov' 

=head1 SYNOPSIS

pima.pl [options]

 Options:
   -version       <integer value>. optional. prefix for store
                  data to database
   -verbose       [1|2] verbose deepth. '1' - not implemented yet.
   -help          brief help message
   -man           full documentation

=head1 OPTIONS

=over 2

=item B<-verbose 1|2>

  Verbose staff output (stderr).
  1 - several parcels on one street line (not implemented yet);
  2 - one parcel detail per one line (default)

  Log legenda for verbose ( for -verbose 2 mode )

    ... suburl part: ok [<NUM1>: <NUM2>,[<NUMn><LETTER>], ... ]
    NUM1 - number or subtables recognized and scraped in ParcelDetail page 
    NUM2 - number of fields recognized in ParcelDetail page
           stored to 'assessor_scrape_<VERSION>' table
    NUMn - number of fields recognized in ParcelDetail page
           and stored to DB tables:
	     LETTER
	     'v' - 'assessor_scrape_valuaton_<VERSION>' table
	     'r' - 'assessor_scrape_recording_<VERSION>' table
	     'e' - 'assessor_scrape_estimate_<VERSION>' table
	   
=item B<-help>

Print a brief help message and exit.

=item B<-man>

Prints the manual  page and exit.

=back

=head1 DESCRIPTION

 pima.pl 
 This script perform scrape and restore remote database through
 "by street" algorithm.

=cut




