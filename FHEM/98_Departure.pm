# $Id: 98_Departure.pm 37909 2016-10-13 08:36:00Z uniqueck $
##############################################################################
#
#     98_Departure.pm
#
#     Calls the URL: http://transportrest-sbiermann.rhcloud.com/departure?from=<stationId>&limit=<departure_max_readings>
#     with the given attributes. 
##############################################################################

use strict;                          
use warnings;                        
use Time::HiRes qw(gettimeofday);    
use HttpUtils;

use LWP;
use Digest::MD5 qw(md5_hex);
use JSON;
use Encode;

my $note_index;

sub Departure_Initialize($) {

    my ($hash) = @_;

    $hash->{DefFn}      = 'Departure_Define';
    $hash->{UndefFn}    = 'Departure_Undef';
    $hash->{SetFn}      = 'Departure_Set';
    $hash->{GetFn}      = 'Departure_Get';
    $hash->{AttrFn}     = 'Departure_Attr';
    $hash->{ReadFn}     = 'Departure_Read';

    $hash->{AttrList} =
          "departure_provider "
	. "departure_base_url "
	. "departure_departure "
	. "departure_max_readings "
	. "departure_time_to_go_to_station "
	. "departure_use_delay_for_time:0,1 "
        . $readingFnAttributes;
}

sub Departure_Define($$) {

    my ( $hash, $def ) = @_;
    my @a = split( "[ \t][ \t]*", $def );
    
    return "Departure_Define - too few parameters: define <name> Departure <interval>" if ( @a < 3 );

    my $name 	= $a[0];
    my $inter	= 300;

    if(int(@a) == 3) { 
       $inter = int($a[2]); 
       if ($inter < 10 && $inter) {
          return "Departure_Define - interval too small, please use something > 10 (sec), default is 300 (sec)";
       }
    }

    $hash->{Interval} = $inter;

    Log3 $name, 3, "Departure_Define ($name) - defined with interval $hash->{Interval} (sec)";

    # initial request after 2 secs, there timer is set to interval for further update
    my $nt = gettimeofday()+$hash->{Interval};
    $hash->{TRIGGERTIME} = $nt;
    $hash->{TRIGGERTIME_FMT} = FmtDateTime($nt);
    RemoveInternalTimer($hash);
    InternalTimer($nt, "Departure_GetDeparture", $hash, 0);

    $hash->{BASE_URL} = AttrVal($name, "departure_base_url", 'http://transportrest-sbiermann.rhcloud.com');

    $hash->{STATE} = 'initialized';
    
    return undef;
}

sub Departure_Undef($$) {
    my ($hash, $arg) = @_; 
    my $name = $hash->{NAME};

    RemoveInternalTimer($hash);

    Log3 $name, 3, "Departure_Undef ($name) - removed";

    return undef;                  
}

sub Departure_Get($@) {

	my ($hash, $name, $cmd, @val) = @_;
   	
	my $list = "provider:noArg ";
	$list .= "stationId" if AttrVal($name,'departure_provider',0);
	
	if ($cmd eq 'provider') {
	
		return Departure_Get_Provider($hash);
	}
	if ($cmd eq 'stationId') {
		Log3 ($hash, 3, "$name: $val[0]"); 		
		return Departure_Find_Stations($hash, $val[0]);
	}
	return "Departure_Get ($name) - Unknown argument $cmd or wrong parameter(s), choose one of $list"; 	
}

sub Departure_Find_Stations($$) {
	
	my ($hash, $val) = @_;
	my $res;
	my $result;

	my $param = {
		url        => "$hash->{BASE_URL}/station/suggest?q=" . $val . "&provider=" . AttrVal($hash->{NAME},"departure_provider",0),
		timeout    => 30,
		hash       => $hash,
		method     => "GET",
		header     => "User-Agent: fhem\r\nAccept: application/json",
	};
	Log3 ($hash, 4, "$hash->{NAME}: get find stations request " . $param->{url});
	my ($err, $data) = HttpUtils_BlockingGet($param);
	Log3 ($hash, 4, "$hash->{NAME}: got find stations response");
	if ($err) {
		Log3 ($hash, 2, "$hash->{NAME}: error $err retriving stations");
	} elsif ($data) {
		Log3 ($hash, 5, "$hash->{NAME}: stations response data $data");
		eval { 
			$res = JSON->new->utf8(1)->decode($data);
		};
		if ($@) {
			Log3 ($hash, 2, "$hash->{NAME}: error decoding stations response $@");
		} else {
			$result = undef;		
			Log3 ($hash, 5, "$hash->{NAME}: stations response data $res->{locations}");			
			foreach my $item (@{$res->{locations}}) {
				# nur solche zulassen, welche auf stationen sind
				if ($item->{type} eq 'STATION') {
					my $station = Encode::encode('UTF-8',$item->{place} . "-" . $item->{name});						
					Log3 ($hash, 5, "$hash->{NAME}: stations $item->{type} $item->{name}");					
					$result .= $item->{id} ."\t" . $station . "\n";				
				}
			
			} 
		}
	}
  return $result;

}

sub Departure_Get_Provider($) {

  my ($hash) = @_;
  my $res;
  my $result = undef;

  my $param = {
    url        => "$hash->{BASE_URL}/provider",
    timeout    => 30,
    hash       => $hash,
    method     => "GET",
    header     => "User-Agent: fhem\r\nAccept: application/json",
    # callback   =>  \&Departure_ParseProvider
  };
  Log3 ($hash, 4, "$hash->{NAME}: get provider request");
  my ($err, $data) = HttpUtils_BlockingGet($param);
  Log3 ($hash, 4, "$hash->{NAME}: got provider response");
  if ($err) {
    	Log3 ($hash, 2, "$hash->{NAME}: error $err retriving provider");
  } elsif ($data) {
  	Log3 ($hash, 5, "$hash->{NAME}: provider response data $data");
    	eval { 
      		$res = JSON->new->utf8(1)->decode($data);
    	};
	if ($@) {
     		Log3 ($hash, 2, "$hash->{NAME}: error decoding provider response $@");
    	} else {
		$result = "";		
		foreach my $item( @$res ) { 
    			Log3 ($hash, 5, "$hash->{NAME}: provider name $item->{name} provider aClass $item->{aClass}");		
			$result .= $item->{name} ."\t" . $item->{aClass} . "\n"; 		
		} 
    	}
  }
  return $result;
}


sub Departure_GetDeparture($) {
	
	my ($hash) = @_;
	my $name = $hash->{NAME};
	my $departure = AttrVal($name, "departure_departure", undef);
	my $provider = AttrVal($name,"departure_provider",undef);
	my $max_readings = AttrVal($name, "departure_max_readings", 10);


	if($hash->{STATE} eq 'active' || $hash->{STATE} eq 'initialized') {
       		my $nt = gettimeofday()+$hash->{Interval};
       		$hash->{TRIGGERTIME} = $nt;
       		$hash->{TRIGGERTIME_FMT} = FmtDateTime($nt);
       		RemoveInternalTimer($hash);
       		InternalTimer($nt, "Departure_GetDeparture", $hash, 1) if (int($hash->{Interval}) > 0);
       		Log3 $name, 5, "Departure ($name) - DB timetable: restartet InternalTimer with $hash->{Interval}";
    	}	
 	
	unless(defined($provider))
    	{
        	Log3 $name, 3, "Departure ($name) - GetDeparture: no valid provider defined";
        	return;
    	}

	unless(defined($departure))
    	{
        	Log3 $name, 3, "Departure ($name) - GetDeparture: no valid departure defined";
        	return;
    	}

	my $param = {
    		url        => "$hash->{BASE_URL}/departure?from=" . $departure . "&provider=" . $provider . "&limit=" . $max_readings,
    		timeout    => 30,
    		hash       => $hash,
    		method     => "GET",
    		header     => "User-Agent: fhem\r\nAccept: application/json",
    		callback   =>  \&Departure_ParseDeparture
  	};
	Log3 ($hash, 4, "$hash->{BASE_URL}/departure?from=" . $departure . "&provider=" . $provider . "&limit=" . $max_readings);
	HttpUtils_NonblockingGet($param);
}

sub Departure_ParseDeparture(@) {
	my ($param, $err, $data) = @_;
	my $hash = $param->{hash};
	my $name = $hash->{NAME};
	my $timeoffset = AttrVal($name, "departure_time_to_go_to_station",0); 	
	my $res;
	fhem("deletereading $hash->{NAME} departure.*", 1);
	Log3 ($hash, 4, "$hash->{NAME}: status code $param->{code}");	
	if ($param->{code} != 200) {
		readingsBeginUpdate($hash);
		readingsBulkUpdate( $hash, "departure_error_http_status_code", $param->{code});								
		readingsBulkUpdate( $hash, "departure_error_url", $param->{url});		
		if ($err) {
			Log3 ($hash, 2, "$hash->{NAME}: error $err retriving departure");
			readingsBulkUpdate( $hash, "departure_error_http_status_text", $err);		
		} elsif ($data) {
			Log3 ($hash, 2, "$hash->{NAME}: error $data retriving departure");
			readingsBulkUpdate( $hash, "departure_error_http_status_text", $data);		
		}
		readingsEndUpdate($hash,1);
		$hash->{STATE}='error' if($hash->{STATE} eq 'initialized' || $hash->{STATE} eq 'active');
	
    	} elsif ($data) {
		Log3 ($hash, 5, "$hash->{NAME}: departure response data $data");
		eval { 
      			$res = JSON->new->utf8(1)->decode($data);
    		};
		if ($@) {
     			Log3 ($hash, 2, "$hash->{NAME}: error decoding departure response $@");
    		} else {	
							
			readingsBeginUpdate($hash);
			my $i = 0;			
			foreach my $item( @$res ) { 
    				readingsBulkUpdate( $hash, "departure_" . $i . "_text", Encode::encode('UTF-8',$item->{to}));
				readingsBulkUpdate( $hash, "departure_" . $i . "_time", $item->{departureTime});
				readingsBulkUpdate( $hash, "departure_" . $i . "_delay", $item->{departureDelay});					 		
				readingsBulkUpdate( $hash, "departure_" . $i . "_timeInMinutes", $item->{departureTimeInMinutes});					 		
				if (defined($timeoffset)) {
					my $temp = $item->{departureTimeInMinutes} - $timeoffset;
					readingsBulkUpdate( $hash, "departure_" . $i . "_time2Go", $temp);							
				} 				
				$i++;			
			}
			readingsEndUpdate($hash,1); 
    		}
		$hash->{STATE}='active' if($hash->{STATE} eq 'initialized' || $hash->{STATE} eq 'error');	
	}
	
	return undef;
}


sub Departure_Set($@) {

   my ($hash, $name, $cmd, @val) = @_;

   my $list = "interval";
   $list .= " update:noArg" if($hash->{STATE} ne 'disabled');

   if ($cmd eq 'interval')
   {
      if (int @val == 1 && $val[0] > 10) 
      {
         $hash->{Interval} = $val[0];

         # initial request after 2 secs, there timer is set to interval for further update
         my $nt	= gettimeofday()+$hash->{Interval};
         $hash->{TRIGGERTIME} = $nt;
         $hash->{TRIGGERTIME_FMT} = FmtDateTime($nt);
         if($hash->{STATE} eq 'active' || $hash->{STATE} eq 'initialized') {
            RemoveInternalTimer($hash);
            InternalTimer($nt, "Departure_GetDeparture", $hash, 0);
            Log3 $name, 3, "Departure_Set ($name) - restarted with new timer interval $hash->{Interval} (sec)";
         } else {
            Log3 $name, 3, "Departure_Set ($name) - new timer interval $hash->{Interval} (sec) will be active when starting/enabling";
         }
		 
         return undef;

      } elsif (int @val == 1 && $val[0] <= 10) {
          Log3 $name, 4, "Departure_Set ($name) - interval: $val[0] (sec) to small, continuing with $hash->{Interval} (sec)";
          return "Departure_Set - interval too small, please use something > 10, defined is $hash->{Interval} (sec)";
      } else {
          Log3 $name, 4, "Departure_Set ($name) - interval: no interval (sec) defined, continuing with $hash->{Interval} (sec)";
          return "Departure_Set - no interval (sec) defined, please use something > 10, defined is $hash->{Interval} (sec)";
      }
   } # if interval
   elsif ($cmd eq 'update')
   {
      Departure_GetDeparture($hash);

      return undef;

   }
   return "Departure_Set ($name) - Unknown argument $cmd or wrong parameter(s), choose one of $list";

}

sub Departure_Attr(@) {
   my ($cmd,$name,$attrName,$attrVal) = @_;
   my $hash = $defs{$name};

   if($cmd eq "set") {
      $attr{$name}{$attrName} = $attrVal;   
      Log3 $name, 4, "Departure_Attr ($name) - set $attrName : $attrVal";
   } elsif ($cmd eq "del") {
      Log3 $name, 4, "Departure_Attr ($name) - deleted $attrName : $attrVal";
   }
   

   return undef;
}


1;

=pod
=begin html

<a name="Departure"></a>
<h3>Departure</h3>


=end html
=cut
