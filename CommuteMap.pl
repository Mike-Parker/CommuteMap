#!/usr/bin/perl

use strict;

use LWP::Simple;
use XML::Simple;
use Image::Magick;
use URI::Escape;
use File::Temp;

# South Glos
#my $lat_min      = 51.31796193777206;
#my $lat_max      = 51.99947567378914;
#my $lng_min      = -2.7493164062500455;
#my $lng_max      = -1.6506835937500455;
#my $scale        = 500000;
#my @destinations = ('GL5+5NN', 'SN13+9DF');

# Knutsford
my $lat_min      = 53.25;
my $lat_max      = 53.35;
my $lng_min      = -2.47;
my $lng_max      = -2.27;
my $scale        = 100000;
my @destinations = ('Knutsford');

my $elements_per_day_limit = 2500;
#my $elements_per_day_limit = 1250;
#my $elements_per_day_limit = 1000;

my $elements_per_ten_seconds_limit = 100;

my $fh = File::Temp->new( UNLINK => 1 );

my $map_filename = $fh->filename;

my $url = "http://tile.openstreetmap.org/cgi-bin/export?bbox=$lng_min,$lat_min,$lng_max,$lat_max&scale=$scale&format=png";

my $http_response = LWP::Simple::getstore($url, $map_filename);

if ($http_response != 200)
{
	print STDERR "\nERROR: Retrieval of map image from OpenStreetMap failed with HTTP error code $http_response\n\n";
	exit;
}

my $img = Image::Magick->new;
$img->Read($map_filename);

my $img_width  = $img->Get('width');
my $img_height = $img->Get('height');

$img->Write(filename => "map.rgb");

print "$img_width x $img_height\n";

exit;

my $aspect_ratio = $img_height / $img_width;

my $destinations_string = "";

my @distances = ();

foreach my $destination (@destinations)
{
  $destinations_string .= $destination."|";
}

chop $destinations_string;

my $max_unique_points = $elements_per_day_limit / scalar(@destinations);

my $num_points_on_lat_axis = int(sqrt($max_unique_points * $aspect_ratio));
my $num_points_on_lng_axis = int($max_unique_points / $num_points_on_lat_axis);

my $lat_increment = ($lat_max - $lat_min)/($num_points_on_lat_axis - 1);
my $lng_increment = ($lng_max - $lng_min)/($num_points_on_lng_axis - 1);

my $lat_px_increment = ($img_height - 1)/($num_points_on_lat_axis - 1);
my $lng_px_increment = ($img_width  - 1)/($num_points_on_lng_axis - 1);

my @coords_array = ();

for my $i (0 .. ($num_points_on_lat_axis - 1))
{
  my $lat    = $lat_min + ($i * $lat_increment);
  my $px_lat = $i * $lat_px_increment;
	
  for my $j (0 .. ($num_points_on_lng_axis - 1))
  {
    my $lng    = $lng_min + ($j * $lng_increment);
    my $px_lng = $j * $lng_px_increment;
		
    push @coords_array, ["$lat,$lng", $px_lng, $px_lat];    
    
    #print "$px_lng $px_lat $lng $lat\n";
  }
}

my $coord_counter = 0;

my $number_coords_per_request = $elements_per_ten_seconds_limit / scalar(@destinations);

# Limit length of (encoded/escaped) URL to 2000 chars
my $url_length_limit = 2000;

while ($coord_counter < scalar(@coords_array))
{
  my $origins_string = "";
  
  my $url = "http://maps.googleapis.com/maps/api/distancematrix/xml?destinations=$destinations_string&sensor=false&origins=";
  
  my $url_stub_length = length(uri_escape($url));

  for my $k (1 .. $number_coords_per_request)
  {
    last if (($coord_counter == scalar(@coords_array)) || (($url_stub_length + length(uri_escape($origins_string))) > $url_length_limit));
  	
    $origins_string .= 	$coords_array[$coord_counter++]->[0]."|";
  }
  
  #Remove trailing pipe
  chop $origins_string;
  
  $url .= $origins_string;  
      
  my $content = get($url);
  
  populate_distances($content);
    
  sleep 10;
}

my $prev_x = 0;

foreach my $destination (0 .. scalar(@destinations)-1)
{
  open(my $fh, ">", $destinations[$destination].".gnu");

  foreach my $l (0 .. scalar(@distances)-1)
  {
    if ($distances[$l][$destination] ne "")
    {
    	# Insert blank lines between horizontal data blocks
    
    	if ($coords_array[$l]->[1] < $prev_x)
	{
		print $fh "\n";
	}
    
      print $fh $coords_array[$l]->[1]." ".$coords_array[$l]->[2]." ".$distances[$l][$destination]."\n";
      
      $prev_x = $coords_array[$l]->[1];
    }
  }
  	
  close($fh);
}

sub populate_distances
{
  my ($infile) = @_;

  my $xs = XML::Simple->new();
  my $xml = $xs->XMLin($infile);
  
  my $status = $xml->{'status'};
  
  if ($status ne "OK")
  {
  	print "\nError: $status\n\n";
	exit;
  }
  
  foreach my $row (@{$xml->{'row'}})
  {
    my @row_array = ();

    if (ref($row->{'element'}) == 2)
    {
      foreach my $element (@{$row->{'element'}})
      {
        if ($element->{'status'} eq "OK")
        {
          push @row_array, $element->{'duration'}{'value'};
        }
        else
        {
          push @row_array, "";
        }
      }
    }
    else
    {
      if ($row->{'element'}{'status'} eq "OK")
      {
        push @row_array, $row->{'element'}{'duration'}{'value'};
      }
      else
      {
        push @row_array, "";
      }   	
    }
	
    push @distances, \@row_array;
  }
}
