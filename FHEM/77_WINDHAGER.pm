####################################################################################################
#
#  77_WINDHAGER.pm
#
#  (c) 2016 Tobias D. Oestreicher
#
#  
#  Connect fhem to Windhager RC7030 
#  inspired by 59_PROPLANTA.pm
#
#  Copyright notice
#
#  This script is free software; you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation; either version 2 of the License, or
#  (at your option) any later version.
#
#  The GNU General Public License can be found at
#  http://www.gnu.org/copyleft/gpl.html.
#  A copy is found in the text file GPL.txt and important notices to the license
#  from the author is found in LICENSE.txt distributed with these scripts.
#
#  This script is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  This copyright notice MUST APPEAR in all copies of the script!
#
#
#
#
####################################################################################################



package main;
use strict;
use warnings;
no if $] >= 5.017011, warnings => 'experimental::lexical_subs','experimental::smartmatch';

my $missingModul;
eval "use LWP::UserAgent;1" or $missingModul .= "LWP::UserAgent ";
eval "use JSON;1" or $missingModul .= "JSON ";
eval "use Encode;1" or $missingModul .= "Encode ";
eval "use Data::Dumper;1" or $missingModul .= "Data::Dumper ";

require 'Blocking.pm';
require 'HttpUtils.pm';
use vars qw($readingFnAttributes);

use vars qw(%defs);
my $MODUL           = "WINDHAGER";
my $version         = "0.0.1";




########################################
sub WINDHAGER_Log($$$) {

    my ( $hash, $loglevel, $text ) = @_;
    my $xline       = ( caller(0) )[2];

    my $xsubroutine = ( caller(1) )[3];
    my $sub         = ( split( ':', $xsubroutine ) )[2];
    $sub =~ s/WINDHAGER_//;

    my $instName = ( ref($hash) eq "HASH" ) ? $hash->{NAME} : $hash;
    Log3 $instName, $loglevel, "$MODUL $instName: $sub.$xline " . $text;
}

###################################
sub WINDHAGER_Initialize($) {

    my ($hash) = @_;
    $hash->{DefFn}    = "WINDHAGER_Define";
    $hash->{UndefFn}  = "WINDHAGER_Undef";
    $hash->{AttrList} = $readingFnAttributes;
   
    foreach my $d(sort keys %{$modules{WINDHAGER}{defptr}}) {
        my $hash = $modules{WINDHAGER}{defptr}{$d};
        $hash->{VERSION}      = $version;
    }
}

###################################
sub WINDHAGER_Define($$) {

    my ( $hash, $def ) = @_;
    my $name = $hash->{NAME};
    my $lang = "";
    my @a    = split( "[ \t][ \t]*", $def );
   
    return "Error: Perl moduls ".$missingModul."are missing on this system" if( $missingModul );
    return "Wrong syntax: use define <name> WINDHAGER [IP] [USER] [PW] [Interval] "  if ( int(@a) != 6 );


        $hash->{STATE}           = "Initializing";
        $hash->{IP}     = $a[2];
        $hash->{USER}     = $a[3];
        $hash->{PW}     = $a[4];
        $hash->{INTERVAL}     = $a[5];
        $hash->{URL} =  "http://".$hash->{IP}."/api/1.0/lookup/";
    
        
        $hash->{fhem}{LOCAL}     = 0;
        $hash->{VERSION}         = $version;
       
        RemoveInternalTimer($hash);
       
        #Get first data after 12 seconds
        InternalTimer( gettimeofday() + 12, "WINDHAGER_Start", $hash, 0 );
   
    return undef;
}

#####################################
sub WINDHAGER_Undef($$) {

    my ( $hash, $arg ) = @_;

    RemoveInternalTimer( $hash );
    BlockingKill( $hash->{helper}{RUNNING_PID} ) if ( defined( $hash->{helper}{RUNNING_PID} ) );
   
    return undef;
}


#####################################
sub WINDHAGER_Start($) {

    my ($hash) = @_;
    my $name   = $hash->{NAME};
   
    return unless (defined($hash->{NAME}));
   
    if(!$hash->{fhem}{LOCAL} && $hash->{INTERVAL} > 0) {        # set up timer if automatically call
    
        RemoveInternalTimer( $hash );
        InternalTimer(gettimeofday() + $hash->{INTERVAL}, "WINDHAGER_Start", $hash, 1 );  
        return undef if( AttrVal($name, "disable", 0 ) == 1 );
    }

  
    $hash->{helper}{RUNNING_PID} =
        BlockingCall( 
            "WINDHAGER_Run",          # callback worker task
            $name,              # name of the device
            "WINDHAGER_Done",         # callback result method
            120,                # timeout seconds
            "WINDHAGER_Aborted",      #  callback for abortion
            $hash );            # parameter for abortion
}

#####################################
sub WINDHAGER_Aborted($) {

    my ($hash) = @_;
    delete( $hash->{helper}{RUNNING_PID} );
}

#####################################
# asyncronous callback by blocking
sub WINDHAGER_Done($) {

    my ($string) = @_;
    return unless ( defined($string) );
   
    # all term are separated by "|" , the first is the name of the instance
    my ( $name, %values ) = split( "\\|", $string );
    my $hash = $defs{$name};
    return unless ( defined($hash->{NAME}) );
   
    # delete the marker for RUNNING_PID process
    delete( $hash->{helper}{RUNNING_PID} );  

    # daten speichern
    readingsBeginUpdate($hash);
    my ($newstate,$kesseltemp,$wassertemp,$phase,$art) = "";
    while (my ($rName, $rValue) = each(%values) ) {
        readingsBulkUpdate( $hash, $rName, $rValue );
        WINDHAGER_Log $hash, 5, "reading:$rName value:$rValue";
        if ( $rName eq "KesselTemp_IST" ) {
            $kesseltemp=$rValue;
        } 
        if ( $rName eq "WarmWasser_IST" ) {
            $wassertemp=$rValue;
        } 
        if ( $rName eq "Betriebsphase" ) {
            $phase=$rValue;
        } 
        if ( $rName eq "Betriebsart" ) {
            $art=$rValue;
        } 
    }
    my $phasestr=WINDHAGER_Phase($phase);
    readingsBulkUpdate( $hash, "Betriebsphase_Str", $phasestr );
    $newstate="Kessel: ".$kesseltemp." - Wasser: ".$wassertemp." - Betriebsphase: ".$phasestr;
    my $artstr=WINDHAGER_Betrieb($art);
    readingsBulkUpdate( $hash, "Betriebsart_Str", $artstr );
    readingsBulkUpdate( $hash, "state", $newstate ); 
    readingsEndUpdate( $hash, 1 );
}


#####################################
sub WINDHAGER_Run($) {

    my ($name) = @_;
    my $ptext=$name;
    
    return unless ( defined($name) );
   
    my $hash = $defs{$name};
    return unless (defined($hash->{NAME}));
    
    my $readingStartTime = time();
    
    my %heizungsdata = (
        'Alarmcode',                  '1/60/0/155/4',
        'Betriebsart',                '1/60/0/155/1',
        'Betriebsphase',              '1/60/0/155/2',
        'Betriebsstunden',            '1/60/0/156/2',
        'Laufzeit_bis_Reinigung',     '1/60/0/156/3',
        'WarmWasser_IST',             '1/15/0/114/0',
        'WarmWasser_SOLL',            '1/15/0/114/1',
        'Aussentemperatur',           '1/15/0/115/0',
        'VorlaufTemp_IST',            '1/15/0/116/0',
        'VorlaufTemp_SOLL',           '1/15/0/116/1',
        'KesselTemp_IST',             '1/60/0/155/0',
        'KesselTemp_SOLL',            '1/60/0/156/0',
        'PufferTemp_Unten',           '1/15/0/118/0',
        'KesselReinigung',            '1/60/0/156/3',
        'Kesselleistung',             '1/60/0/156/7',
        'AbgasTemperatur',            '1/60/0/156/9',
        'Brennerstarts',              '1/60/0/156/8',
        'Pelletsverbrauch',           '1/60/0/156/10'
    );
    
    


    my $maxCount=5;
    my $Count=0;
    my $ua = LWP::UserAgent->new;
    $ua->credentials($hash->{IP}.':80', 'RC7000', $hash->{USER}, $hash->{PW});
    
    my $message;
    my $i=0;
    my @heizungsattrnames = keys %heizungsdata;
    foreach my $heizungsattrname (@heizungsattrnames) {
         
        my $url2=$hash->{URL}.$heizungsdata{$heizungsattrname};
        my $response = $ua->get($url2);
        $Count=0;
        while ( ! $response->is_success && $Count le $maxCount) {
          $response = $ua->get($url2);
          $Count++;
        }
        my $out = encode_utf8($response->content);
        $out = decode_json $out;
        my @names = keys %$out;
        if('unit' ~~ @names) 
          { 
            WINDHAGER_Log $hash, 4, $heizungsattrname.": "."$out->{'value'} $out->{'unit'}";
            $message .= $heizungsattrname."|"."$out->{'value'} $out->{'unit'}"."|";

          }
        elsif ( defined $out->{'value'} ) 
          {
            WINDHAGER_Log $hash, 4, $heizungsattrname.": "."$out->{'value'}";
            $message .= $heizungsattrname."|"."$out->{'value'}"."|";
          }
        else
          {
            WINDHAGER_Log $hash, 4, $heizungsattrname.": "."no connection";
            $message .= $heizungsattrname."|"."no connection"."|";
          }
        $i++;
    }    
    

    $message .= "durationFetchReadings|";
    $message .= sprintf "%.2f",  time() - $readingStartTime;
    
    WINDHAGER_Log $hash, 3, "Done fetching data";
    WINDHAGER_Log $hash, 4, "Will return : "."$name|$message" ;
    
    return "$name|$message" ;
}



sub WINDHAGER_Betrieb($)
{
        use Switch;
        my ($val) = @_;
        switch ($val) {
                case 0          { return "Switched off" }
                case 1          { return "Shut-down procedure" }
                case 2          { return "Solid fuel/ buffer mode" }
                case 3          { return "Pellet feed in operation" }
                case 4          { return "Pellet feed" }
                case 5          { return "On" }
                case 6          { return "Pellet feed in operation" }
                case 7          { return "Pellet feed" }
                case 8          { return "Manual mode" }
                case 9          { return "Chimney sweeper func" }
                case 10         { return "Actuator test" }
                case 11         { return "Installation procedure active" }
        }
}

sub WINDHAGER_Phase($)
{
        use Switch;
        my ($val) = @_;
        switch ($val) {
                case 0          { return "Brenner gesperrt" }
                case 1          { return "Selbst-Test" }
                case 2          { return "Switch-off heat gener." }
                case 3          { return "Bereitschaft" }
                case 4          { return "Brenner Aus" }
                case 5          { return "Säuberung" }
                case 6          { return "Zündphase" }
                case 7          { return "Flammenstabilisierung" }
                case 8          { return "Modulationsmodus" }
                case 9          { return "Brenner gesperrt" }
                case 10         { return "Stand-by off period" }
                case 11         { return "Fan OFF" }
                case 12         { return "Cladding door open" }
                case 13         { return "Zündung bereit" }
                case 14         { return "Zündphase abbrechen" }
                case 15         { return "Start procedure" }
                case 16         { return "Step-loading" }
                case 17         { return "Ausbrennen" }
        }

}


sub WINDHAGER_ASHTML()
{
  my $ret = '';
  $ret .= '<table id="ZentralheizungsWidget"><tr><td>';
  $ret .= '<table class="block wide"><tr><th></th><th></th></tr>';
  $ret .= '<tr><td class="zhIcon" style="vertical-align:top;">';

  $ret .= '<div id="ZentralheizungsWidgetDetails" style="position: relative; top: 0px; left: 0px; width:1192px; height:771px;">';
  $ret .= '  <div id="BGPicZentralheizungsWidget" style="position: absolute; top: 0px; left: 0px;">';
  $ret .= '    <img src="http://192.168.0.40:8083/fhem/images/default/ZentralHeizungSchema.png">';
  $ret .= '  </div>';
  $ret .= '  <div id="KesselDetails" style="opacity: 0.8; position: absolute; top: 100px; left: 475px; border:5px; border-radius: 25px; background: #847f7f; padding: 20px; width: 160px;   height: 80px; ">';
  $ret .= '    <div style="position: absolute; top: 20px; left: 20px;">Ist:</div> <div style="position: absolute; top: 20px; left: 120px;">'.ReadingsVal('Zentralheizung',"KesselTemp_IST","").'</div>';
  $ret .= '    <div style="position: absolute; top: 40px; left: 20px;">Soll:</div> <div style="position: absolute; top: 40px; left: 120px;">'.ReadingsVal('Zentralheizung',"KesselTemp_SOLL","").'</div>';
  $ret .= '    ';
  $ret .= '    <div style="position: absolute; top: 80px; left: 20px;">Reinigung:</div> <div style="position: absolute; top: 80px; left: 120px;">'.ReadingsVal('Zentralheizung',"KesselReinigung","").'</div>';
  $ret .= '  </div>';
  $ret .= '';
  $ret .= '';
  $ret .= '  <div id="HeizkoerperDetails" style="opacity: 0.8; position: absolute; top: 280px; left: 770px; border:5px; border-radius: 25px; background: #847f7f; padding: 20px; width: 90px; height: 20px; ">';
  $ret .= '    <div style="position: absolute; top: 20px; left: 20px;">Ist:</div> <div style="position: absolute; top: 20px; left: 60px;">'.ReadingsVal('Zentralheizung',"VorlaufTemp_IST","").'</div>';
#  $ret .= '    <div style="position: absolute; top: 40px; left: 20px;">Soll:</div> <div style="position: absolute; top: 40px; left: 60px;">'.ReadingsVal('Zentralheizung',"VorlaufTemp_SOLL","").'</div>';
  $ret .= '  </div>';
  $ret .= '';
  $ret .= '';
  $ret .= '  <div id="FussbodenHeizungDetails" style="opacity: 0.8; position: absolute; top: 385px; left: 1070px; border:5px; border-radius: 25px; background: #847f7f; padding: 20px; width: 90px; height: 20px; ">';
  $ret .= '    <div style="position: absolute; top: 20px; left: 20px;">Ist:</div> <div style="position: absolute; top: 20px; left: 70px;">55 °C</div>';
#  $ret .= '    <div style="position: absolute; top: 40px; left: 20px;">Soll:</div> <div style="position: absolute; top: 40px; left: 70px;">22</div>';
  $ret .= '  </div>';
  $ret .= '';
  $ret .= '';
  $ret .= '  <div id="WarmWasserDetails" style="opacity: 0.8; position: absolute; top: 320px; left: 90px; border:5px; border-radius: 25px; background: #847f7f; padding: 20px; width: 90px; height: 40px; ">';
  $ret .= '    <div style="position: absolute; top: 20px; left: 20px;">Ist:</div> <div style="position: absolute; top: 20px; left: 60px;">'.ReadingsVal('Zentralheizung',"WarmWasser_IST","").'</div>';
  $ret .= '    <div style="position: absolute; top: 40px; left: 20px;">Soll:</div> <div style="position: absolute; top: 40px; left: 60px;">'.ReadingsVal('Zentralheizung',"WarmWasser_SOLL","").'</div>';
  $ret .= '  </div>';
  $ret .= '';
  $ret .= '';
  $ret .= '  <div id="VorlaufDetails" style="opacity: 0.8; position: absolute; top: 490px; left: 810px; border:5px; border-radius: 25px; background: #847f7f; padding: 20px; width: 90px; height:   40px; ">';
  $ret .= '    <div style="position: absolute; top: 20px; left: 20px;">Ist:</div> <div style="position: absolute; top: 20px; left: 60px;">'.ReadingsVal('Zentralheizung',"VorlaufTemp_IST","").'</div>';
  $ret .= '    <div style="position: absolute; top: 40px; left: 20px;">Soll:</div> <div style="position: absolute; top: 40px; left: 60px;">'.ReadingsVal('Zentralheizung',"VorlaufTemp_SOLL","").'</div>';
  $ret .= '  </div>';
  $ret .= '';
  $ret .= '  <div id="PufferTempUntenDetails" style="opacity: 0.8; position: absolute; top: 674px; left: 295px; border:5px; border-radius: 25px; background: #847f7f; padding: 20px; width: 90px; height: 20px; ">';
  $ret .= '    <div style="position: absolute; top: 20px; left: 20px;">Ist:</div> <div style="position: absolute; top: 20px; left: 60px;">'.ReadingsVal('Zentralheizung',"PufferTemp_Unten","").'</div>';
  $ret .= '  </div>';
  $ret .= '';
  $ret .= '  <div id="SolarDetails" style="opacity: 0.8; position: absolute; top: 120px; left: 260px; border:5px; border-radius: 25px; background: #847f7f; padding: 20px; width: 100px; height: 40px; ">';
  $ret .= '    <div style="position: absolute; top: 20px; left: 20px;">Vor:</div> <div style="position: absolute; top: 20px; left: 60px;">'.ReadingsVal("vorlauf","state","").' °C</div>';
  $ret .= '    <div style="position: absolute; top: 40px; left: 20px;">R&uuml;ck:</div> <div style="position: absolute; top: 40px; left: 60px;">'.ReadingsVal("ruecklauf","state","").' °C</div>';
  $ret .= '  </div>';
  $ret .= '';
  $ret .= '';
  $ret .= '  <div id="AussenTempDetails" style="opacity: 0.8; position: absolute; top: 15px; left: 1000px; border:5px; border-radius: 25px; background: #847f7f; padding: 20px; width: 110px; height: 20px; ">';
  $ret .= '    <div style="position: absolute; top: 20px; left: 20px;">Aussen:</div> <div style="position: absolute; top: 20px; left: 80px;">'.ReadingsVal('Zentralheizung',"Aussentemperatur","").'</div>';
  $ret .= '  </div>';
  $ret .= '';
  $ret .= '  <div id="SolarDeltaDetails" style="opacity: 0.8; position: absolute; top: 300px; left: 300px; border:5px; border-radius: 25px; background: #847f7f; padding: 20px; width: 200px; height: 20px; ">';
  $ret .= '    <div style="position: absolute; top: 20px; left: 20px;">&Delta;:</div> <div style="position: absolute; top: 20px; left: 50px;">'.ReadingsVal("vor_rueck_diff","state","").' °C</div>';
  $ret .= '  </div>';
  $ret .= '';
  $ret .= '';

  $ret .= '</div>';
  $ret .= '</td></tr>';
  $ret .= '</table>';



  return $ret;
}





##################################### 
1;





=pod
=begin html

<a name="WINDHAGER"></a>
<h3>WINDHAGER</h3>
<ul>
   <a name="WINDHAGERdefine"></a>
   This modul connects to a RC7030 ebus Gateway by Windhager Heating Systems.
   <br/>
   Additional the module provides a functions to create a HTML-Template which can be used with weblink.
   <br>
   <i>The following Perl-Modules are used within this module: HTTP::Request, LWP::UserAgent, JSON, Encode</i>.
   <br/><br/>
   <b>Define</b>
   <ul>
      <br>
      <code>define &lt;Name&gt; WINDHAGER [IP] [USER] [PW] [INTERVAL]</code>
      <br><br><br>
      Example:
      <br>
      <code>
        define Zentralheizung WINDHAGER 192.168.0.30 Service mypassword 300<br>
        <br>
        define ZentralheizungWidget weblink htmlCode {WINDHAGER_ASHTML()}<br>
      </code>
      <br>&nbsp;

      <li><code>[IP]</code>
         <br>
         Local IP Addres of the RC7030<br/>
      </li><br>
      <li><code>[USER]</code>
         <br>
         User to log in RC7030 (normaly: Service)
         <br>
      </li><br>
      <li><code>[PW]</code>
         <br>
         Password to log in RC7030.
         <br>
      </li><br>
      <li><code>[INTERVAL]</code>
         <br>
         Interval to refetch readings. (A good value can be 300)
         <br>
      </li><br>


      <br><br><br>

   </ul>
   <br>

  
    <br>

   <a name="WINDHAGERreading"></a>
   <b>Readings</b>
   <ul>
      <br>
      <li><b>AbgasTemperatur</b>  </li>
      <li><b>Alarmcode</b>  </li>
      <li><b>Aussentemperatur</b>  </li>
      <li><b>Betriebsart</b>  </li>
      <li><b>Betriebsart_Str</b>  </li>
      <li><b>Betriebsphase</b>  </li>
      <li><b>Betriebsphase_Str</b>  </li>
      <li><b>Betriebsstunden</b>  </li>
      <li><b>Brennerstarts</b>  </li>
      <li><b>KesselReinigung</b>  </li>
      <li><b>KesselTemp_IST</b>  </li>
      <li><b>KesselTemp_SOLL</b>  </li>
      <li><b>Kesselleistung</b>  </li>
      <li><b>Pelletsverbrauch</b>  </li>
      <li><b>PufferTemp_Unten</b>  </li>
      <li><b>VorlaufTemp_IST</b>  </li>
      <li><b>VorlaufTemp_SOLL</b>  </li>
      <li><b>WarmWasser_IST</b>  </li>
      <li><b>WarmWasser_SOLL</b>  </li>
   </ul>
   <br>

   <a name="WINDHAGERweblinks"></a>
   <b>Weblinks</b>
   <ul>
      <br>

      With the additional implemented functions <code>WINDHAGER_ASHTML</code> HTML-Code will be created to display a schema pic using weblinks.
      <br><br><br>
      Example:
      <br>
      <li><code>define ZentralheizungWeblink weblink htmlCode {WINDHAGER_ASHTML()}</code></li>
      <br>
      <br/><br/>
   </ul>
   <br>
 

</ul> 



=end html

=begin html_DE

<a name="WINDHAGER"></a>
<h3>WINDHAGER</h3> 
<ul>
   <a name="WINDHAGERdefine"></a>
   Das Modul ruft Daten über einen RC7030 (ebus GW) der Firma Windhager ab.
   <br/>
   Weiterhin verfügt das Modul über ein HTML-Template welche als weblink verwendet werden kann.
   <br>
   <i>Es nutzt die Perl-Module HTTP::Request, LWP::UserAgent, JSON, Encode</i>.
   <br/><br/>
   <b>Define</b>
   <ul>
      <br>
      <code>define &lt;Name&gt; WINDHAGER [IP] [USER] [PW] [INTERVAL]</code>
      <br><br><br>
      Beispiel:
      <br>
      <code>define Unwetterzentrale WINDHAGER 192.168.0.30 Service geheim 300</code>
      <br>&nbsp;

      <li><code>[IP]</code>
         <br>
         IP des RC7030
      </li><br>
      <li><code>[USER]</code>
         <br>
         Benutzer für Anmeldung. (Normal: Service). 
         <br>
      </li><br>
      <li><code>[PW]</code>
         <br>
         Passwort für Anmeldung.
         <br>
      </li><br>

      <li><code>[INTERVAL]</code>
         <br>
         Definiert das Interval zur Aktualisierung. Das Interval wird in Sekunden angegeben, somit aktualisiert das Modul bei einem Interval von 3600 jede Stunde 1 mal. 
         <br>
      </li><br>
   </ul>
   <br>
   <br>

   <a name="WINDHAGERreading"></a>
   <b>Readings</b>
   <ul>
      <br>
      <li><b>AbgasTemperatur</b>  </li>
      <li><b>Alarmcode</b>  </li>
      <li><b>Aussentemperatur</b>  </li>
      <li><b>Betriebsart</b>  </li>
      <li><b>Betriebsart_Str</b>  </li>
      <li><b>Betriebsphase</b>  </li>
      <li><b>Betriebsphase_Str</b>  </li>
      <li><b>Betriebsstunden</b>  </li>
      <li><b>Brennerstarts</b>  </li>
      <li><b>KesselReinigung</b>  </li>
      <li><b>KesselTemp_IST</b>  </li>
      <li><b>KesselTemp_SOLL</b>  </li>
      <li><b>Kesselleistung</b>  </li>
      <li><b>Pelletsverbrauch</b>  </li>
      <li><b>PufferTemp_Unten</b>  </li>
      <li><b>VorlaufTemp_IST</b>  </li>
      <li><b>VorlaufTemp_SOLL</b>  </li>
      <li><b>WarmWasser_IST</b>  </li>
      <li><b>WarmWasser_SOLL</b>  </li>
   </ul>
   <br>

   <a name="WINDHAGERweblinks"></a>
   <b>Weblinks</b>
   <ul>
      <br>

      &Uuml;ber die Funktionen <code>WINDHAGER_ASHTML</code> wird HTML-Code zur Anzeige als Schemadarstellung über weblinks erzeugt.
      <br><br><br>
      Beispiele:
      <br>
      <li><code>define ZentralheizungWeblink weblink htmlCode {WINDHAGER_ASHTML()}</code></li>
      <br>
      <br/><br/>
   </ul>
   <br>
 

</ul>

=end html_DE
=cut
