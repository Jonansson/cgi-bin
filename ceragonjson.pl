#!"C:\Strawberry\perl\bin\perl.exe"

use JSON;
use LWP::Simple;
use Data::Dumper;
use DBI;

my @head = qw{ip SysName PeakUtilization[%] AverageUtilization[%] PeakCapacity[Mbps] AverageCapacity[Mbps] Dashboard};

my %type = ( "1.3.6.1.4.1.2281.1.1" => "FA1528",
			"1.3.6.1.4.1.2281.1.20.1.3.1" => "IP-20G",
			"1.3.6.1.4.1.2281.1.20.2.2.3" => "IP-20E",
			"1.3.6.1.4.1.2281.1.4" => "FA1500FE",
			"1.3.6.1.4.1.2281.1.4.4" => "FA1500R",
			"1.3.6.1.4.1.2281.1.7.1" => "IP-10R1",
			"1.3.6.1.4.1.2281.1.7.2" => "IP-10G",
			"1.3.6.1.4.1.2281.1.7.3" => "IP-10G Shelf",
			"1.3.6.1.4.1.2281.1.7.7" => "IP-10E",
			"1.3.6.1.4.1.2281.1.7.8" => "IP-10E Shelf" );

#Get InfluxDB statistics data and decode to Perl scalar

# InfluxDB query
my $query = qq{
SELECT MAX(peak_utilization) AS PeakUtilization, 
		MEAN(average_utilization) AS AverageUtilization, 
		MAX(peak_capacity) AS PeakCapacity, 
		MEAN(average_capacity) AS AverageCapacity 
FROM ethernet 
WHERE time > now() - 7d 
GROUP BY ip};  

# Get JSON data from InfluxDB server and decode to perl scalar
my $json = decode_json get qq{http://10.205.0.17:8086/query?pretty=true&db=pm&q=$query};

# Keep only "series" part
my $rows = $json->{"results"}->[0]->{"series"};

# Transform series structure to plain hashs
my @data = map{Serie2Hash($_)}@$rows;

sub Serie2Hash ($){
	my $row = shift;
	my %data = Arr2Hash($row->{"columns"}, $row->{"values"}->[0]);
	return {%data, %{$row->{"tags"}}};	
} 

# Get additional data (obj_id and SysName) from PolyView

my $dbh = DBI->connect("DBI:mysql:database=polyview;host=10.205.0.6;port=3306", "perl", "script") || die;

my $sth = $dbh->prepare_cached(qq{SELECT obj_id, SysName FROM node WHERE IP=?});

for (0..$#data){
	$sth->execute($data[$_]->{"ip"});
	($data[$_]->{"obj_id"}, $data[$_]->{"SysName"})  = $sth->fetchrow_array;	
}
$sth->finish;
$dbh->disconnect;

# Format cells to public view
@data = map{MakeRow($_)}@data;

sub MakeRow ($) {
	my $dat = shift;
	my @rez;
	$rez[0] = sprintf(qq{<a href=\"http://%s\" target=\"_blank\">%s</a> },$dat->{"ip"}, $dat->{"ip"});
	$rez[1] = $type{$dat->{"obj_id"}}." ".$dat->{"SysName"};
	$rez[2] = $dat->{"PeakUtilization"} ;
	$rez[3] = sprintf("%.1f", $dat->{"AverageUtilization"});
#	@rez[2,3] = ($dat->{"PeakUtilization"}, $dat->{"AverageUtilization"});
#	@rez[2,3] = map{ $dat->{"obj_id"} =~ /1.3.6.1.4.1.2281.1.7/ ? $_/1000000 : $_ }@rez[2,3];
#	@rez[2,3] = map{ sprintf("%.1f",$_)} @rez[2,3] ;
	@rez[4,5] = map{ sprintf("%.1f",$_)} map{ $dat->{"obj_id"} =~ /1.3.6.1.4.1.2281.1.7/ ? $_/1000000 : $_ }($dat->{"PeakCapacity"},$dat->{"AverageCapacity"});
	$rez[6] = sprintf(qq{<a href=\"http://10.205.0.17:3000/dashboard/script/ceragon.js?ip=%s&title=%s&capacityexpr=%s\" target=\"_blank\">Dashboard</a> },$dat->{"ip"}, $rez[1], $dat->{"obj_id"} =~ /1.3.6.1.4.1.2281.1.7/ ? "/1000000" : "/1");
	return \@rez;
}

# The final makeup for presentation to javascript
@data = sort { $b->[2]*$b->[3] <=> $a->[2]*$a->[3] } @data;
 
@data = map{Array2Hash($_)}\@head, @data;

sub Array2Hash ($) {
	my $arref = shift;
	return {map{ "col".$_, $arref->[$_] } 0..$#{$arref}};
}

# The end
print "Content-type: text/json; charset=iso-8859-1\n\n";
print  to_json(\@data, , {utf8 => 1, pretty => 0});

exit;

sub Arr2Hash ($$) {
	my ($key, $val) = @_;
	return map{$key->[$_],$val->[$_]}0..$#{$key};
}

