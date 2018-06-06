#!/usr/bin/perl

# grabber for fetching data from DarkSky
# fetches weather data (current and forecast) from DarkSky

# Copyright 2016-2018 Michael Schlenstedt, michael@loxberry.de
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

use strict;
use warnings;

##########################################################################
# Modules
##########################################################################

use LoxBerry::System;
use LoxBerry::Log;
use LWP::UserAgent;
use JSON qw( decode_json ); 
use File::Copy;
use Getopt::Long;
use Time::Piece;

##########################################################################
# Read Settings
##########################################################################

# Version of this script
my $version = "4.3.0";

#my $cfg             = new Config::Simple("$home/config/system/general.cfg");
#my $lang            = $cfg->param("BASE.LANG");
#my $installfolder   = $cfg->param("BASE.INSTALLFOLDER");
#my $miniservers     = $cfg->param("BASE.MINISERVERS");
#my $clouddns        = $cfg->param("BASE.CLOUDDNS");

my $pcfg         = new Config::Simple("$lbpconfigdir/weather4lox.cfg");
my $url          = $pcfg->param("DARKSKY.URL");
my $apikey       = $pcfg->param("DARKSKY.APIKEY");
my $lang         = $pcfg->param("DARKSKY.LANG");
my $stationid    = $pcfg->param("DARKSKY.COORDLAT") . "," . $pcfg->param("DARKSKY.COORDLONG");
my $city         = $pcfg->param("DARKSKY.STATION");
my $country      = $pcfg->param("DARKSKY.COUNTRY");

# Read language phrases

######
###### Workaround
######
use LoxBerry::Web;
use CGI;
my $cgi = CGI->new;
# Template
my $template = HTML::Template->new(
    filename => "$lbptemplatedir/settings.html",
    global_vars => 1,
    loop_context_vars => 1,
    die_on_bad_params => 0,
);
######
######
######
my %L = LoxBerry::System::readlanguage($template, "language.ini");

# Create a logging object
my $log = LoxBerry::Log->new ( 	name => 'grabber_darksky',
			filename => "$lbplogdir/weather4lox.log",
			append => 1,
);

# Commandline options
my $verbose = '';

GetOptions ('verbose' => \$verbose,
            'quiet'   => sub { $verbose = 0 });

# Due to a bug in the Logging routine, set the loglevel fix to 3
#$log->loglevel(3);
if ($verbose) {
	$log->stdout(1);
	$log->loglevel(7);
}

LOGSTART "Weather4Lox GRABBER_DARKSKY process started";
LOGDEB "This is $0 Version $version";

# Get data from Wunderground Server (API request) for current conditions
my $queryurlcr = "$url\/forecast\/$apikey\/$stationid?lang=$lang&units=si&exclude=flags,alerts,minutely";

LOGINF "Fetching Data for Location $stationid";
LOGDEB "URL: $queryurlcr";

my $ua = new LWP::UserAgent;
my $res = $ua->get($queryurlcr);
my $json = $res->decoded_content();

# Check status of request
my $urlstatus = $res->status_line;
my $urlstatuscode = substr($urlstatus,0,3);

LOGDEB "Status: $urlstatus";

if ($urlstatuscode ne "200") {
  LOGCRIT "Failed to fetch data for $stationid\. Status Code: $urlstatuscode";
  LOGEND "Exit.";
  exit 2;
} else {
  LOGOK "Data fetched successfully for $stationid";
}

# Decode JSON response from server
my $decoded_json = decode_json( $json );

# Write location data into database
my $t = localtime($decoded_json->{currently}->{time});
LOGINF "Saving new Data for Timestamp $t to database.";

#print "Debug: ", $tz, "\n";
#exit;

# Saving new current data...
my $error = 0;
open(F,">$lbplogdir/current.dat.tmp") or $error = 1;
	if ($error) {
		LOGCRIT "Cannot open $lbpconfigdir/current.dat.tmp";
  		LOGEND "Exit.";
		exit 2;
	}
	binmode F, ':encoding(UTF-8)';
	print F "$decoded_json->{currently}->{time}|";
	print F $t, " ", sprintf("+%04d", $decoded_json->{offset} * 100), "|";
	print F "-9999|";
	print F "$decoded_json->{timezone}|";
	print F sprintf("+%04d", $decoded_json->{offset} * 100), "|";
	print F "$city|";
	print F "$country|";
	print F "-9999|";
	print F $pcfg->param("SERVER.DARKSKYCOORDLAT"), "|";
	print F $pcfg->param("SERVER.DARKSKYCOORDLONG"), "|";
	# Convert elevation from feet to meter
	print F "-9999|";
	print F sprintf("%.1f",$decoded_json->{currently}->{temperature}), "|";
	print F sprintf("%.1f",$decoded_json->{currently}->{apparentTemperature}), "|";
	print F $decoded_json->{currently}->{humidity} * 100, "|";
	my $wdir = $decoded_json->{currently}->{windBearing};
	my $wdirdes;
	if ( $wdir >= 0 && $wdir <= 22 ) { $wdirdes = $L{'SETTINGS.LABEL_N'} }; # North
	if ( $wdir > 22 && $wdir <= 68 ) { $wdirdes = $L{'SETTINGS.LABEL_NE'} }; # NorthEast
	if ( $wdir > 68 && $wdir <= 112 ) { $wdirdes = $L{'SETTINGS.LABEL_E'} }; # East
	if ( $wdir > 112 && $wdir <= 158 ) { $wdirdes = $L{'SETTINGS.LABEL_SE'} }; # SouthEast
	if ( $wdir > 158 && $wdir <= 202 ) { $wdirdes = $L{'SETTINGS.LABEL_S'} }; # South
	if ( $wdir > 202 && $wdir <= 248 ) { $wdirdes = $L{'SETTINGS.LABEL_SW'} }; # SouthWest
	if ( $wdir > 248 && $wdir <= 292 ) { $wdirdes = $L{'SETTINGS.LABEL_W'} }; # West
	if ( $wdir > 292 && $wdir <= 338 ) { $wdirdes = $L{'SETTINGS.LABEL_NW'} }; # NorthWest
	if ( $wdir > 338 && $wdir <= 360 ) { $wdirdes = $L{'SETTINGS.LABEL_N'} }; # North
	print F "$wdirdes|";
	print F "$decoded_json->{currently}->{windBearing}|";
	print F sprintf("%.1f",$decoded_json->{currently}->{windSpeed} * 3.6), "|";
	print F sprintf("%.1f",$decoded_json->{currently}->{windGust} * 3.6), "|";
	print F sprintf("%.0f",$decoded_json->{currently}->{apparentTemperature}), "|";
	print F "$decoded_json->{currently}->{pressure}|";
	print F sprintf("%.1f",$decoded_json->{currently}->{dewPoint}), "|";
	print F "$decoded_json->{currently}->{visibility}|";
	print F "-9999|";
	print F "-9999|";
	print F "$decoded_json->{currently}->{uvIndex}|";
	print F "-9999|";
	print F sprintf("%.3f",$decoded_json->{currently}->{precipIntensity}), "|";
	# Convert Weather string into Weather Code and convert icon name
	my $weather = $decoded_json->{currently}->{icon};
	$weather =~ s/\-night|\-day//; # No -night and -day
	$weather =~ s/\-//; # No -
	$weather =~ tr/A-Z/a-z/; # All Lowercase
	print F "$weather|"; # Icon
	if ($weather eq "clear") {$weather = "1";}
	#elsif ($weather eq "sunny") {$weather = "1";}
	#elsif ($weather eq "partlysunny") {$weather = "3";}
	#elsif ($weather eq "mostlysunny") {$weather = "2";}
	elsif ($weather eq "partlycloudy") {$weather = "2";}
	#elsif ($weather eq "mostlycloudy") {$weather = "3";}
	elsif ($weather eq "cloudy") {$weather = "4";}
	#elsif ($weather eq "overcast") {$weather = "4";}
	#elsif ($weather eq "chanceflurries") {$weather = "18";}
	#elsif ($weather eq "chancesleet") {$weather = "18";}
	#elsif ($weather eq "chancesnow") {$weather = "20";}
	#elsif ($weather eq "flurries") {$weather = "16";}
	elsif ($weather eq "sleet") {$weather = "19";}
	elsif ($weather eq "snow") {$weather = "21";}
	#elsif ($weather eq "chancerain") {$weather = "12";}
	elsif ($weather eq "rain") {$weather = "13";}
	#elsif ($weather eq "chancetstorms") {$weather = "14";}
	#elsif ($weather eq "tstorms") {$weather = "15";}
	elsif ($weather eq "fog") {$weather = "6";}
	#elsif ($weather eq "hazy") {$weather = "5";}
	elsif ($weather eq "wind") {$weather = "22";}
	else {$weather = "0";}
	print F "$weather|";
	print F "$decoded_json->{currently}->{summary}|";
	print F $decoded_json->{daily}->{data}->[0]->{moonPhase}*100, "|";
	print F "-9999|";
	print F "-9999|";
	print F "-9999|";
	$t = localtime($decoded_json->{daily}->{data}->[0]->{sunriseTime});
	print F $t->hour, "|";
	print F sprintf("%02d", $t->min), "|";
	$t = localtime($decoded_json->{daily}->{data}->[0]->{sunsetTime});
	print F $t->hour, "|";
	print F sprintf("%02d", $t->min), "|";
	print F "$decoded_json->{currently}->{ozone}|";
	print F $decoded_json->{currently}->{cloudCover}*100, "|";
	print F $decoded_json->{currently}->{precipProbability}*100, "|";
close(F);

LOGOK "Saving current data to $lbplogdir/current.dat.tmp successfully.";

my @filecontent;
LOGDEB "Database content:";
open(F,"<$lbplogdir/current.dat.tmp");
	@filecontent = <F>;
	foreach (@filecontent) {
		chomp ($_);
		LOGDEB "$_";
	}
close (F);

# Saving new daily forecast data...
$error = 0;
open(F,">$lbplogdir/dailyforecast.dat.tmp") or $error = 1;
	if ($error) {
		LOGCRIT "Cannot open $lbplogdir/dailyforecast.dat.tmp";
  		LOGEND "Exit.";
		exit 2;
	}
	binmode F, ':encoding(UTF-8)';
	my $i = 1;
	for my $results( @{$decoded_json->{daily}->{data}} ){
		print F "$i|";
		$i++;
		print F $results->{time}, "|";
		$t = localtime($results->{time});
		print F sprintf("%02d", $t->mday), "|";
		print F sprintf("%02d", $t->mon), "|";
		print F $t->fullmonth . "|";
		print F $t->monname . "|";
		print F $t->year . "|";
		print F sprintf("%02d", $t->hour), "|";
		print F sprintf("%02d", $t->min), "|";
		print F $t->fullday . "|";
		print F $t->wdayname . "|";
		print F sprintf("%.1f",$results->{apparentTemperatureHigh}), "|";
		print F sprintf("%.1f",$results->{apparentTemperatureLow}), "|";
		print F $results->{precipProbability}*100, "|";
		print F sprintf("%.3f",$results->{precipIntensity}), "|";
		print F "-9999|";
		print F sprintf("%.1f",$results->{windGust} * 3.6), "|";
		$wdir = $results->{windBearing};
		if ( $wdir >= 0 && $wdir <= 22 ) { $wdirdes = $L{'SETTINGS.LABEL_N'} }; # North
		if ( $wdir > 22 && $wdir <= 68 ) { $wdirdes = $L{'SETTINGS.LABEL_NE'} }; # NorthEast
		if ( $wdir > 68 && $wdir <= 112 ) { $wdirdes = $L{'SETTINGS.LABEL_E'} }; # East
		if ( $wdir > 112 && $wdir <= 158 ) { $wdirdes = $L{'SETTINGS.LABEL_SE'} }; # SouthEast
		if ( $wdir > 158 && $wdir <= 202 ) { $wdirdes = $L{'SETTINGS.LABEL_S'} }; # South
		if ( $wdir > 202 && $wdir <= 248 ) { $wdirdes = $L{'SETTINGS.LABEL_SW'} }; # SouthWest
		if ( $wdir > 248 && $wdir <= 292 ) { $wdirdes = $L{'SETTINGS.LABEL_W'} }; # West
		if ( $wdir > 292 && $wdir <= 338 ) { $wdirdes = $L{'SETTINGS.LABEL_NW'} }; # NorthWest
		if ( $wdir > 338 && $wdir <= 360 ) { $wdirdes = $L{'SETTINGS.LABEL_N'} }; # North
		print F "$wdirdes|";
		print F "$results->{windBearing}|";
		print F sprintf("%.1f",$results->{windSpeed} * 3.6), "|";
		print F "$wdirdes|";
		print F "$results->{windBearing}|";
		print F $results->{humidity}*100, "|";
		print F $results->{humidity}*100, "|";
		print F $results->{humidity}*100, "|";
		$weather = $results->{icon};
		$weather =~ s/\-night|\-day//; # No -night and -day
		$weather =~ s/\-//; # No -
		$weather =~ tr/A-Z/a-z/; # All Lowercase
		print F "$weather|"; # Icon
		if ($weather eq "clear") {$weather = "1";}
		#elsif ($weather eq "sunny") {$weather = "1";}
		#elsif ($weather eq "partlysunny") {$weather = "3";}
		#elsif ($weather eq "mostlysunny") {$weather = "2";}
		elsif ($weather eq "partlycloudy") {$weather = "2";}
		#elsif ($weather eq "mostlycloudy") {$weather = "3";}
		elsif ($weather eq "cloudy") {$weather = "4";}
		#elsif ($weather eq "overcast") {$weather = "4";}
		#elsif ($weather eq "chanceflurries") {$weather = "18";}
		#elsif ($weather eq "chancesleet") {$weather = "18";}
		#elsif ($weather eq "chancesnow") {$weather = "20";}
		#elsif ($weather eq "flurries") {$weather = "16";}
		elsif ($weather eq "sleet") {$weather = "19";}
		elsif ($weather eq "snow") {$weather = "21";}
		#elsif ($weather eq "chancerain") {$weather = "12";}
		elsif ($weather eq "rain") {$weather = "13";}
		#elsif ($weather eq "chancetstorms") {$weather = "14";}
		#elsif ($weather eq "tstorms") {$weather = "15";}
		elsif ($weather eq "fog") {$weather = "6";}
		#elsif ($weather eq "hazy") {$weather = "5";}
		elsif ($weather eq "wind") {$weather = "22";}
		else {$weather = "0";}
		print F "$weather|";
		print F "$results->{summary}|";
		print F sprintf("%.1f",$results->{dewPoint}), "|";
		print F $results->{moonPhase}*100, "|";
		print F sprintf("%.1f",$results->{dewPoint}), "|";
		print F "$results->{pressure}|";
		print F "$results->{uvIndex}|";
		$t = localtime($results->{sunriseTime});
		print F sprintf("%02d", $t->hour), "|";
		print F sprintf("%02d", $t->min), "|";
		$t = localtime($results->{sunsetTime});
		print F sprintf("%02d", $t->hour), "|";
		print F sprintf("%02d", $t->min), "|";
		print F "\n";
	}
close(F);

LOGOK "Saving daily forecast data to $lbplogdir/dailyforecast.dat.tmp successfully.";

LOGDEB "Database content:";
open(F,"<$lbplogdir/dailyforecast.dat.tmp");
	@filecontent = <F>;
	foreach (@filecontent) {
		chomp ($_);
		LOGDEB "$_";
	}
close (F);

# Saving new hourly forecast data...
$error = 0;
open(F,">$lbplogdir/hourlyforecast.dat.tmp") or $error = 1;
	if ($error) {
		LOGCRIT "Cannot open $lbplogdir/hourlyforecast.dat.tmp";
  		LOGEND "Exit.";
		exit 2;
	}
	binmode F, ':encoding(UTF-8)';
	$i = 1;
	for my $results( @{$decoded_json->{hourly}->{data}} ){
		print F "$i|";
		$i++;
		print F $results->{time}, "|";
		$t = localtime($results->{time});
		print F sprintf("%02d", $t->mday), "|";
		print F sprintf("%02d", $t->mon), "|";
		print F $t->fullmonth . "|";
		print F $t->monname . "|";
		print F $t->year . "|";
		print F sprintf("%02d", $t->hour), "|";
		print F sprintf("%02d", $t->min), "|";
		print F $t->fullday . "|";
		print F $t->wdayname . "|";
		print F sprintf("%.1f",$results->{temperature}), "|";
		print F sprintf("%.1f",$results->{apparentTemperature}), "|";
		print F "-9999|";
		print F $results->{humidity}*100, "|";
		$wdir = $results->{windBearing};
		if ( $wdir >= 0 && $wdir <= 22 ) { $wdirdes = $L{'SETTINGS.LABEL_N'} }; # North
		if ( $wdir > 22 && $wdir <= 68 ) { $wdirdes = $L{'SETTINGS.LABEL_NE'} }; # NorthEast
		if ( $wdir > 68 && $wdir <= 112 ) { $wdirdes = $L{'SETTINGS.LABEL_E'} }; # East
		if ( $wdir > 112 && $wdir <= 158 ) { $wdirdes = $L{'SETTINGS.LABEL_SE'} }; # SouthEast
		if ( $wdir > 158 && $wdir <= 202 ) { $wdirdes = $L{'SETTINGS.LABEL_S'} }; # South
		if ( $wdir > 202 && $wdir <= 248 ) { $wdirdes = $L{'SETTINGS.LABEL_SW'} }; # SouthWest
		if ( $wdir > 248 && $wdir <= 292 ) { $wdirdes = $L{'SETTINGS.LABEL_W'} }; # West
		if ( $wdir > 292 && $wdir <= 338 ) { $wdirdes = $L{'SETTINGS.LABEL_NW'} }; # NorthWest
		if ( $wdir > 338 && $wdir <= 360 ) { $wdirdes = $L{'SETTINGS.LABEL_N'} }; # North
		print F "$wdirdes|";
		print F "$results->{windBearing}|";
		print F sprintf("%.1f",$results->{windSpeed} * 3.6), "|";
		print F sprintf("%.1f",$results->{windGust} * 3.6), "|";
		print F "$results->{pressure}|";
		print F sprintf("%.1f",$results->{dewPoint}), "|";
		print F $results->{cloudCover}*100, "|";
		print F "-9999|";
		print F "$results->{uvIndex}|";
		print F sprintf("%.3f",$results->{precipIntensity}), "|";
		print F "-9999|";
		print F $results->{precipProbability}*100, "|";
		$weather = $results->{icon};
		$weather =~ s/\-night|\-day//; # No -night and -day
		$weather =~ s/\-//; # No -
		$weather =~ tr/A-Z/a-z/; # All Lowercase
		my $icon = $weather;
		if ($weather eq "clear") {$weather = "1";}
		#elsif ($weather eq "sunny") {$weather = "1";}
		#elsif ($weather eq "partlysunny") {$weather = "3";}
		#elsif ($weather eq "mostlysunny") {$weather = "2";}
		elsif ($weather eq "partlycloudy") {$weather = "2";}
		#elsif ($weather eq "mostlycloudy") {$weather = "3";}
		elsif ($weather eq "cloudy") {$weather = "4";}
		#elsif ($weather eq "overcast") {$weather = "4";}
		#elsif ($weather eq "chanceflurries") {$weather = "18";}
		#elsif ($weather eq "chancesleet") {$weather = "18";}
		#elsif ($weather eq "chancesnow") {$weather = "20";}
		#elsif ($weather eq "flurries") {$weather = "16";}
		elsif ($weather eq "sleet") {$weather = "19";}
		elsif ($weather eq "snow") {$weather = "21";}
		#elsif ($weather eq "chancerain") {$weather = "12";}
		elsif ($weather eq "rain") {$weather = "13";}
		#elsif ($weather eq "chancetstorms") {$weather = "14";}
		#elsif ($weather eq "tstorms") {$weather = "15";}
		elsif ($weather eq "fog") {$weather = "6";}
		#elsif ($weather eq "hazy") {$weather = "5";}
		elsif ($weather eq "wind") {$weather = "22";}
		else {$weather = "0";}
		print F "$weather|";
		print F "$icon|"; # Icon
		print F "$results->{summary}|";
		print F "$results->{ozone}|";
		print F "\n";
	}
close(F);

LOGOK "Saving hourly forecast data to $lbplogdir/hourlyforecast.dat.tmp successfully.";

LOGDEB "Database content:";
open(F,"<$lbplogdir/hourlyforecast.dat.tmp");
	@filecontent = <F>;
	foreach (@filecontent) {
		chomp ($_);
		LOGDEB "$_";
	}
close (F);

# Clean Up Databases
LOGINF "Cleaning $lbplogdir/current.dat.tmp";
open(F,"+<$lbplogdir/current.dat.tmp");
	@filecontent = <F>;
	seek(F,0,0);
	truncate(F,0);
	foreach (@filecontent){
		s/[\n\r]//g;
		if($_ =~ /^#/) {
		  print F "$_\n";
		  next;
		}
		LOGDEB "Original: $_";
		s/\|null\|/"|0|"/eg;
		s/\|--\|/"|0|"/eg;
		s/\|na\|/"|-9999.00|"/eg;
		s/\|NA\|/"|-9999.00|"/eg;
		s/\|n\/a\|/"|-9999.00|"/eg;
		s/\|N\/A\|/"|-9999.00|"/eg;
		LOGDEB "Cleaned:  $_";
		print F "$_\n";
	}
close(F);

LOGINF "Cleaning $lbplogdir/dailyforecast.dat.tmp";
open(F,"+<$lbplogdir/dailyforecast.dat.tmp");
	@filecontent = <F>;
	seek(F,0,0);
	truncate(F,0);
	foreach (@filecontent){
		s/[\n\r]//g;
		if($_ =~ /^#/) {
		  print F "$_\n";
		  next;
		}
		LOGDEB "Original: $_";
		s/\|null\|/"|0|"/eg;
		s/\|--\|/"|0|"/eg;
		s/\|na\|/"|-9999.00|"/eg;
		s/\|NA\|/"|-9999.00|"/eg;
		s/\|n\/a\|/"|-9999.00|"/eg;
		s/\|N\/A\|/"|-9999.00|"/eg;
		LOGDEB "Cleaned:  $_";
		print F "$_\n";
	}
close(F);

LOGINF "Cleaning $lbplogdir/hourlyforecast.dat.tmp";
open(F,"+<$lbplogdir/hourlyforecast.dat.tmp");
	@filecontent = <F>;
	seek(F,0,0);
	truncate(F,0);
	foreach (@filecontent){
		s/[\n\r]//g;
		if($_ =~ /^#/) {
		  print F "$_\n";
		  next;
		}
		LOGDEB "Original: $_";
		s/\|null\|/"|0|"/eg;
		s/\|--\|/"|0|"/eg;
		s/\|na\|/"|-9999.00|"/eg;
		s/\|NA\|/"|-9999.00|"/eg;
		s/\|n\/a\|/"|-9999.00|"/eg;
		s/\|N\/A\|/"|-9999.00|"/eg;
		LOGDEB "Cleaned:  $_";
		print F "$_\n";
	}
close(F);

# Test downloaded files
my $currentname = "$lbplogdir/current.dat.tmp";
my $currentsize = -s ($currentname);
if ($currentsize > 100) {
        move($currentname, "$lbplogdir/current.dat");
}
my $dailyname = "$lbplogdir/dailyforecast.dat.tmp";
my $dailysize = -s ($dailyname);
if ($dailysize > 100) {
        move($dailyname, "$lbplogdir/dailyforecast.dat");
}
my $hourlyname = "$lbplogdir/hourlyforecast.dat.tmp";
my $hourlysize = -s ($hourlyname);
if ($hourlysize > 100) {
        move($hourlyname, "$lbplogdir/hourlyforecast.dat");
}

# Give OK status to client.
LOGOK "Current Data and Forecasts saved successfully.";

# Exit
LOGEND "Exit.";
exit;

