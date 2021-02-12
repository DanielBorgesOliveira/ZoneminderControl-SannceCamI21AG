# ==========================================================================
#
# ZoneMinder Sannce Cam I21AG Module
# Copyright (C) 2020  Daniel Oliveira
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
#
# =========================================================================================
#
# This module contains an implementation of the SannceCam I21AG camera control
# protocol
#
package ZoneMinder::Control::SannceCamI21AG;

use 5.006;
use strict;
use warnings;

require ZoneMinder::Base;
require ZoneMinder::Control;

our @ISA = qw(ZoneMinder::Control);
our $VERSION = $ZoneMinder::Base::VERSION;

our %CamParams = ();
$CamParams{'contrast'} = 127;
$CamParams{'brightness'} = 127;
# ==========================================================================
#
# SannceCam I21AG camera control
#
# Set the following:
# ControlAddress: username:password@camera_webaddress:port
# ControlDevice: IP Camera Model
#
# ==========================================================================
use ZoneMinder::Logger qw(:all);
use ZoneMinder::Config qw(:all);

use Time::HiRes qw( usleep );

use LWP::UserAgent;
use HTTP::Cookies;

my $ChannelID = 1;
my $user = 'fool';
my $pass = 'bar';
my $host = '0.0.0.0';
my $port = '80';

our %ptz = ();
$ptz{'PTZ_UP'} = 0;
$ptz{'PTZ_UP_STOP'} = 1;
$ptz{'PTZ_DOWN'} = 2;
$ptz{'PTZ_DOWN_STOP'} = 3;
$ptz{'PTZ_LEFT'} = 4;
$ptz{'PTZ_LEFT_STOP'} = 5;
$ptz{'PTZ_RIGHT'} = 6;
$ptz{'PTZ_RIGHT_STOP'} =7;
$ptz{'PTZ_LEFT_UP'} = 90;
$ptz{'PTZ_RIGHT_UP'} = 91;
$ptz{'PTZ_LEFT_DOWN'} = 92;
$ptz{'PTZ_RIGHT_DOWN'} = 93;
$ptz{'PTZ_STOP'} = 1;
$ptz{'PTZ_CENTER'} = 25;

$ptz{'Preset1'} = 30;
$ptz{'Preset2'} = 32;
$ptz{'Preset3'} = 34;
$ptz{'Preset4'} = 36;
$ptz{'Preset5'} = 38;
$ptz{'Preset6'} = 40;
$ptz{'Preset7'} = 42;
$ptz{'Preset8'} = 44;
$ptz{'Preset9'} = 46;
$ptz{'Preset10'} = 48;
$ptz{'Preset11'} = 50;
$ptz{'Preset12'} = 52;
$ptz{'Preset13'} = 54;
$ptz{'Preset14'} = 56;
$ptz{'Preset15'} = 58;
$ptz{'Preset16'} = 60;

sub open
{
  my $self = shift;
  $self->loadMonitor();
  #
  # Create a UserAgent for the requests
  #
  $self->{UA} = LWP::UserAgent->new();
  $self->{UA}->cookie_jar( {} );
  #
  # Extract the username/password host/port from ControlAddress
  #
  if ( $self->{Monitor}{ControlAddress} =~ /^([^:]+):([^@]+)@(.+)/ ) { # user:pass@host...
    $user = $1;
    $pass = $2;
    $host = $3;
  } elsif ( $self->{Monitor}{ControlAddress} =~ /^([^@]+)@(.+)/ ) { # user@host...
    $user = $1;
    $host = $2;
  } else { # Just a host
    $host = $self->{Monitor}{ControlAddress};
  }
  # Check if it is a host and port or just a host
  if ( $host =~ /([^:]+):(.+)/ ) {
    $host = $1;
    $port = $2;
  } else {
    $port = 80;
  }
  # Save the credentials
  if ( defined($user) ) {
    $self->{UA}->credentials("$host:$port", $self->{Monitor}{ControlDevice}, $user, $pass);
  }
  # Save the base url
  $self->{BaseURL} = "http://$host:$port";

}
sub close
{
	my $self = shift;
	$self->{state} = 'closed';
}
sub sendCmd {
  my $self = shift;
  my $cmd = shift;
  my $content = shift;
  #Warning("Subindo \"$self->{BaseURL}.'/'.$cmd\". Control Devi");
  my $req = HTTP::Request->new(GET => $self->{BaseURL}.'/'.$cmd);
  if ( defined($content) ) {
    $req->content_type('application/x-www-form-urlencoded; charset=UTF-8');
    $req->content('<?xml version="1.0" encoding="UTF-8"?>' . "\n" . $content);
  }
  my $res = $self->{UA}->request($req);
  unless( $res->is_success ) {
    #
    # The camera timeouts connections at short intervals. When this
    # happens the user agent connects again and uses the same auth tokens.
    # The camera rejects this and asks for another token but the UserAgent
    # just gives up. Because of this I try the request again and it should
    # succeed the second time if the credentials are correct.
    #
    if ( $res->code == 401 ) {
      $res = $self->{UA}->request($req);
      unless( $res->is_success ) {
        #
        # It has failed authentication. The odds are
        # that the user has set some parameter incorrectly
        # so check the realm against the ControlDevice
        # entry and send a message if different
        #
        my $auth = $res->headers->www_authenticate;
        foreach (split(/\s*,\s*/,$auth)) {
          if ( $_ =~ /^realm\s*=\s*"([^"]+)"/i ) {
            if ( $self->{Monitor}{ControlDevice} ne $1 ) {
              Warning("Control Device appears to be incorrect.
                Control Device should be set to \"$1\".
                Control Device currently set to \"$self->{Monitor}{ControlDevice}\".");
              $self->{Monitor}{ControlDevice} = $1;
              $self->{UA}->credentials("$host:$port", $self->{Monitor}{ControlDevice}, $user, $pass);
              return sendCmd($self,$cmd,$content);
            }
          }
        }
        #
        # Check for username/password
        #
        if ( $self->{Monitor}{ControlAddress} =~ /.+:(.+)@.+/ ) {
          Info('Check username/password is correct');
        } elsif ( $self->{Monitor}{ControlAddress} =~ /^[^:]+@.+/ ) {
          Info('No password in Control Address. Should there be one?');
        } elsif ( $self->{Monitor}{ControlAddress} =~ /^:.+@.+/ ) {
          Info('Password but no username in Control Address.');
        } else {
          Info('Missing username and password in Control Address.');
        }
        Error($res->status_line);
      }
    } else {
      Error($res->status_line);
    }
  } # end unless res->is_success
} # end sub sendCmd
#Up Arrow
sub moveConUp
{
	Debug( "Move Up" );
	my $self = shift;
	my $params = shift;
	my $cmd = "decoder_control.cgi?loginuse=$user&loginpas=$pass&command=$ptz{'PTZ_UP'}&onestep=1";
	$self->sendCmd( $cmd );
}
sub moveConDown
{
	Debug( "Move Down" );
	my $self = shift;
	my $params = shift;
	my $cmd = "decoder_control.cgi?loginuse=$user&loginpas=$pass&command=$ptz{'PTZ_DOWN'}&onestep=1";
	$self->sendCmd( $cmd );
}
sub moveConLeft
{
	Debug( "Move Down" );
	my $self = shift;
	my $params = shift;
	my $cmd = "decoder_control.cgi?loginuse=$user&loginpas=$pass&command=$ptz{'PTZ_LEFT'}&onestep=1";
	$self->sendCmd( $cmd );
}
sub moveConRight
{
	Debug( "Move Down" );
	my $self = shift;
	my $params = shift;
	my $cmd = "decoder_control.cgi?loginuse=$user&loginpas=$pass&command=$ptz{'PTZ_RIGHT'}&onestep=1";
	$self->sendCmd( $cmd );
}
sub moveStop
{
	Debug( "Move Stop" );
	my $self = shift;
	my $params = shift;
	my $cmd = "decoder_control.cgi?loginuse=$user&loginpas=$pass&command=$ptz{'PTZ_STOP'}&onestep=0";
	$self->sendCmd( $cmd );
}
sub presetSet
{
	my $self = shift;
    my $params = shift;
    my $preset = $self->getParam( $params, 'preset' );
    Debug( "Set Preset $preset" );
    my $cmdNum = $ptz{'Preset'.$preset};
	my $cmd = "decoder_control.cgi?loginuse=$user&loginpas=$pass&command=$cmdNum&onestep=0&sit=$cmdNum";
    $self->sendCmd( $cmd );
}
sub presetGoto
{
    my $self = shift;
    my $params = shift;
    my $preset = $self->getParam( $params, 'preset' );
    Debug( "Goto Preset $preset" );
	my $cmdNum = $ptz{'Preset'.$preset}+1;
	my $cmd = "decoder_control.cgi?loginuse=$user&loginpas=$pass&command=$cmdNum&onestep=0&sit=$cmdNum";
    $self->sendCmd( $cmd );
}
# Increase Contrast
sub whiteAbsIn
{
	my $self = shift;
	my $params = shift;
	my $step = $self->getParam( $params, 'step' );
	my $param = 2;

	$CamParams{'contrast'} += $step;
	$CamParams{'contrast'} = 255 if ($CamParams{'contrast'} > 255);
	Debug( "Iris $CamParams{'contrast'}" );
	my $cmd = "camera_control.cgi?loginuse=".$user."&loginpas=".$pass."&param=".$param."&value=".$CamParams{'contrast'};
	$self->sendCmd( $cmd );
}
# Decrease Contrast
sub whiteAbsOut
{
	my $self = shift;
	my $params = shift;
	my $step = $self->getParam( $params, 'step' );
	my $param = 2;

	$CamParams{'contrast'} -= $step;
	$CamParams{'contrast'} = 0 if ($CamParams{'contrast'} < 0);
	Debug( "Iris $CamParams{'contrast'}" );
	my $cmd = "camera_control.cgi?loginuse=".$user."&loginpas=".$pass."&param=".$param."&value=".$CamParams{'contrast'};
	$self->sendCmd( $cmd );
}
sub irisAbsOpen
{
	my $self = shift;
	my $params = shift;
	my $step = $self->getParam( $params, 'step' );
	my $param = 1;

	$CamParams{'brightness'} += $step;
	$CamParams{'brightness'} = 255 if ($CamParams{'brightness'} > 255);
	Debug( "Iris $CamParams{'brightness'}" );
	my $cmd = "camera_control.cgi?loginuse=".$user."&loginpas=".$pass."&param=".$param."&value=".$CamParams{'brightness'};
	$self->sendCmd( $cmd );
}
sub irisAbsClose
{
	my $self = shift;
	my $params = shift;
	my $step = $self->getParam( $params, 'step' );
	my $param = 1;

	$CamParams{'brightness'} -= $step;
	$CamParams{'brightness'} = 0 if ($CamParams{'brightness'} < 0);
	Debug( "Iris $CamParams{'brightness'}" );
	my $cmd = "camera_control.cgi?loginuse=".$user."&loginpas=".$pass."&param=".$param."&value=".$CamParams{'brightness'};
	$self->sendCmd( $cmd );
}
__END__
# Enable Infrared
http://192.168.1.100:80/camera_control.cgi?loginuse=admin&loginpas=[Password]&param=14&value=1
# Disable Infrared
http://192.168.1.100:80/camera_control.cgi?loginuse=admin&loginpas=[Password]&param=14&value=0

# Constant Bit Rate (CBR) OFF
http://192.168.1.100:80/camera_control.cgi?loginuse=admin&loginpas=[Password]&param=21&value=0
# Constant Bit Rate (CBR) ON
http://192.168.1.100:80/camera_control.cgi?loginuse=admin&loginpas=[Password]&param=21&value=1

# Tilt Speed. Value from 1 to 10.
http://192.168.1.100:80/camera_control.cgi?loginuse=admin&loginpas=[Password]&param=100&value=10

# Contrast from 0 to 255
http://192.168.1.100:80/camera_control.cgi?loginuse=admin&loginpas=[Password]&param=2&value=0

# Brightness from 0 to 255
http://192.168.1.100:80/camera_control.cgi?loginuse=admin&loginpas=[Password]&param=1&value=0

Color Saturation from 0 to 255
http://192.168.1.100:80/camera_control.cgi?loginuse=admin&loginpas=[Password]&param=8&value=255

Color Chroma from 0 to 255
http://192.168.1.100:80/camera_control.cgi?loginuse=admin&loginpas=[Password]&param=9&value=255

# Mirror Vertically OFF
http://192.168.1.100:80/camera_control.cgi?loginuse=admin&loginpas=[Password]&param=5&value=0
# Mirror Vertically ON
http://192.168.1.100:80/camera_control.cgi?loginuse=admin&loginpas=[Password]&param=5&value=1

# Mirror Horizontally OFF
http://192.168.1.100:80/camera_control.cgi?loginuse=admin&loginpas=[Password]&param=5&value=0
# Mirror Horizontally ON
http://192.168.1.100:80/camera_control.cgi?loginuse=admin&loginpas=[Password]&param=5&value=1

# Environment "Indoor 50Hz"
http://192.168.1.100:80/camera_control.cgi?loginuse=admin&loginpas=[Password]&param=3&value=0
# Environment "Indoor 60Hz"
http://192.168.1.100:80/camera_control.cgi?loginuse=admin&loginpas=[Password]&param=3&value=1
# Environment "Outdoor 50Hz"
http://192.168.1.100:80/camera_control.cgi?loginuse=admin&loginpas=[Password]&param=3&value=2
# Environment "Outdoor 60Hz"
http://192.168.1.100:80/camera_control.cgi?loginuse=admin&loginpas=[Password]&param=3&value=3

# Camera resolution 640x360
http://192.168.1.100:80/camera_control.cgi?loginuse=admin&loginpas=[Password]&param=15&value=0
# Camera resolution 320x180
http://192.168.1.100:80/camera_control.cgi?loginuse=admin&loginpas=[Password]&param=15&value=1

# Camera 5 Frames per Second (FPS)
http://192.168.1.100:80/camera_control.cgi?loginuse=admin&loginpas=[Password]&param=6&value=5
# Camera 10 Frames per Second (FPS)
http://192.168.1.100:80/camera_control.cgi?loginuse=admin&loginpas=[Password]&param=6&value=10
# Camera 15 Frames per Second (FPS)
http://192.168.1.100:80/camera_control.cgi?loginuse=admin&loginpas=[Password]&param=6&value=15
# Camera 20 Frames per Second (FPS)
http://192.168.1.100:80/camera_control.cgi?loginuse=admin&loginpas=[Password]&param=6&value=20
# Camera 25 Frames per Second (FPS)
http://192.168.1.100:80/camera_control.cgi?loginuse=admin&loginpas=[Password]&param=6&value=25

# Audio Bitrate from 128 to 4096 (Need verification)
http://192.168.1.100:80/camera_control.cgi?loginuse=admin&loginpas=[Password]&param=13&value=128

# Audio Volume from 1 to 31
http://192.168.1.100:80/camera_control.cgi?loginuse=admin&loginpas=[Password]&param=24&value=0

# Camera Speaker Volume from 1 to 31
http://192.168.1.100:80/camera_control.cgi?loginuse=admin&loginpas=[Password]&param=25&value=31

# Set Preseted Position
http://192.168.1.100:80/decoder_control.cgi?loginuse=admin&loginpas=[Password]&command=30&onestep=0&sit=30
http://192.168.1.100:80/decoder_control.cgi?loginuse=admin&loginpas=[Password]&command=32&onestep=0&sit=32
http://192.168.1.100:80/decoder_control.cgi?loginuse=admin&loginpas=[Password]&command=34&onestep=0&sit=34
http://192.168.1.100:80/decoder_control.cgi?loginuse=admin&loginpas=[Password]&command=36&onestep=0&sit=36
http://192.168.1.100:80/decoder_control.cgi?loginuse=admin&loginpas=[Password]&command=38&onestep=0&sit=38
http://192.168.1.100:80/decoder_control.cgi?loginuse=admin&loginpas=[Password]&command=40&onestep=0&sit=40
http://192.168.1.100:80/decoder_control.cgi?loginuse=admin&loginpas=[Password]&command=42&onestep=0&sit=42
http://192.168.1.100:80/decoder_control.cgi?loginuse=admin&loginpas=[Password]&command=44&onestep=0&sit=44
http://192.168.1.100:80/decoder_control.cgi?loginuse=admin&loginpas=[Password]&command=46&onestep=0&sit=46
http://192.168.1.100:80/decoder_control.cgi?loginuse=admin&loginpas=[Password]&command=48&onestep=0&sit=48
http://192.168.1.100:80/decoder_control.cgi?loginuse=admin&loginpas=[Password]&command=50&onestep=0&sit=50
http://192.168.1.100:80/decoder_control.cgi?loginuse=admin&loginpas=[Password]&command=52&onestep=0&sit=52
http://192.168.1.100:80/decoder_control.cgi?loginuse=admin&loginpas=[Password]&command=54&onestep=0&sit=54
http://192.168.1.100:80/decoder_control.cgi?loginuse=admin&loginpas=[Password]&command=56&onestep=0&sit=56
http://192.168.1.100:80/decoder_control.cgi?loginuse=admin&loginpas=[Password]&command=58&onestep=0&sit=58
http://192.168.1.100:80/decoder_control.cgi?loginuse=admin&loginpas=[Password]&command=60&onestep=0&sit=60

# Go to Preset
http://192.168.1.100:80/decoder_control.cgi?loginuse=admin&loginpas=[Password]&command=31&onestep=0&sit=31
http://192.168.1.100:80/decoder_control.cgi?loginuse=admin&loginpas=[Password]&command=33&onestep=0&sit=33
http://192.168.1.100:80/decoder_control.cgi?loginuse=admin&loginpas=[Password]&command=35&onestep=0&sit=35
http://192.168.1.100:80/decoder_control.cgi?loginuse=admin&loginpas=[Password]&command=37&onestep=0&sit=37
http://192.168.1.100:80/decoder_control.cgi?loginuse=admin&loginpas=[Password]&command=39&onestep=0&sit=39
http://192.168.1.100:80/decoder_control.cgi?loginuse=admin&loginpas=[Password]&command=41&onestep=0&sit=41
http://192.168.1.100:80/decoder_control.cgi?loginuse=admin&loginpas=[Password]&command=43&onestep=0&sit=43
http://192.168.1.100:80/decoder_control.cgi?loginuse=admin&loginpas=[Password]&command=45&onestep=0&sit=45
http://192.168.1.100:80/decoder_control.cgi?loginuse=admin&loginpas=[Password]&command=47&onestep=0&sit=47
http://192.168.1.100:80/decoder_control.cgi?loginuse=admin&loginpas=[Password]&command=49&onestep=0&sit=49
http://192.168.1.100:80/decoder_control.cgi?loginuse=admin&loginpas=[Password]&command=51&onestep=0&sit=51
http://192.168.1.100:80/decoder_control.cgi?loginuse=admin&loginpas=[Password]&command=53&onestep=0&sit=53
http://192.168.1.100:80/decoder_control.cgi?loginuse=admin&loginpas=[Password]&command=55&onestep=0&sit=55
http://192.168.1.100:80/decoder_control.cgi?loginuse=admin&loginpas=[Password]&command=57&onestep=0&sit=57
http://192.168.1.100:80/decoder_control.cgi?loginuse=admin&loginpas=[Password]&command=59&onestep=0&sit=59
http://192.168.1.100:80/decoder_control.cgi?loginuse=admin&loginpas=[Password]&command=61&onestep=0&sit=61

# Setup PTZ Settings
http://192.168.1.100:80/set_misc.cgi?next_url=ptz.htm&loginuse=admin&loginpas=[Password]&ptz_patrol_rate=10&ptz_patrol_up_rate=10&ptz_patrol_down_rate=10&ptz_patrol_left_rate=10&ptz_patrol_right_rate=10&ptz_dispreset=0&ptz_preset=1&led_mode=1&ptz_run_times=0

# Get snapshot
http://192.168.1.100:80/snapshot.cgi?&loginuse=admin&loginpas=[Password]&user=admin&pwd=[Password]

# Get camera status
http://192.168.1.100:80/get_status.cgi?&loginuse=admin&loginpas=[Password]&user=admin&pwd=[Password]

# Get cameras parameters
http://192.168.1.100:80/get_params.cgi?&loginuse=admin&loginpas=[Password]&user=admin&pwd=[Password]
