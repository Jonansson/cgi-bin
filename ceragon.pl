#!"C:\Strawberry\perl\bin\perl.exe"
print "Content-type: text/html; charset=iso-8859-1\n\n";
print qq{<meta http-equiv="refresh" content="0; url=http://10.205.0.17:3000/dashboard/script/ceragontable.js" />};

exit;

use JSON::Parse 'parse_json';
use LWP::Simple;
use Data::Dumper;
use HTML::Table;
use DBI;
use Number::Format;

my $number = new Number::Format(-thousands_sep   => ' ',
                            -decimal_point   => '.');
                            

my $dbh = DBI->connect("DBI:mysql:database=polyview;host=10.205.0.6;port=3306", "perl", "script") || die;

my $sth = $dbh->prepare_cached(qq{SELECT obj_id, SysName FROM node WHERE IP=?});


my %type = ( "1.3.6.1.4.1.2281.1.1" => "FA1528",
"1.3.6.1.4.1.2281.1.20.1.3.1" => "IP-20G",
"1.3.6.1.4.1.2281.1.20.2.2.3" => "IP-20E",
"1.3.6.1.4.1.2281.1.4" => "FA1500FE",
"1.3.6.1.4.1.2281.1.4.4" => "FA1500R",
"1.3.6.1.4.1.2281.1.7.1" => "IP-10R1",
"1.3.6.1.4.1.2281.1.7.2" => "IP-10G",
"1.3.6.1.4.1.2281.1.7.3" => "IP-10G Shelf",
"1.3.6.1.4.1.2281.1.7.7" => "IP-10E",
"1.3.6.1.4.1.2281.1.7.8" => "IP-10E Shelf");



my $query = qq{
SELECT MAX(peak_utilization) AS PeakUtilization, 
		MEAN(average_utilization) AS AverageUtilization, 
		MAX(peak_capacity) AS PeakCapacity, 
		MEAN(average_capacity) AS AverageCapacity 
FROM ethernet 
WHERE time > now() - 7d 
GROUP BY ip};  

my $json = get qq{http://10.205.0.17:8086/query?pretty=true&db=pm&q=$query};

my $rows = parse_json($json)->{"results"}->[0]->{"series"};

my @head = qw{ip SysName PeakUtilization[%] AverageUtilization[%] PeakCapacity[Mbps] AverageCapacity[Mbps] Dashboard};

my @data;
foreach my $row (@$rows){

$sth->execute($row->{"tags"}->{"ip"});
my ($obj_id, $SysName)  = $sth->fetchrow_array;

my @dat = (
sprintf(qq{<a href="http://%s" target="_blank">%s</a> },$row->{"tags"}->{"ip"}, $row->{"tags"}->{"ip"}),
$type{$obj_id}." ".$SysName,
$row->{"values"}->[0]->[1],
sprintf("%.1f", $row->{"values"}->[0]->[2]),



$number->format_number(sprintf("%.1f", ( $obj_id =~ /1.3.6.1.4.1.2281.1.7/ ? $row->{"values"}->[0]->[3] / 1000000 : $row->{"values"}->[0]->[3]))),
$number->format_number(sprintf("%.1f", ( $obj_id =~ /1.3.6.1.4.1.2281.1.7/ ? $row->{"values"}->[0]->[4] / 1000000 : $row->{"values"}->[0]->[4]))),

sprintf(qq{<a href="http://10.205.0.17:3000/dashboard/script/ceragon.js?ip=%s&title=%s&capacityexpr=%s" target="_blank">Dashboard</a> },$row->{"tags"}->{"ip"}, $type{$obj_id}." ".$SysName, $obj_id =~ /1.3.6.1.4.1.2281.1.7/ ? "/1000000" : "/1")
);

push @data, \@dat;
}
$sth->finish;
@data = sort { $b->[3] <=> $a->[3] } @data;
#@data = sort { $b->[2] <=> $a->[2] } @data;

#if ( $ENV{"QUERY_STRING"} =~ /json/i ){
	
#print "Content-type: text/json; charset=iso-8859-1\n\n";

##print "<h1>JSON</H1>\n\n";
 
#my $json = "[";

#foreach my $arref (@data){
	#my @row = @$arref;
	#$json .= "\{";
	#foreach my $colnum	(0..$#row){
		#$json .= "sprintf(qq{\"col\u%\": \"\s%, \"}, $colnum, $row[$colnum] );
		#}
	#$json .= "\},";
	#}
#$json .= "\]";
#} 
#print "$json\n";
#exit;	
# }


my $table = new HTML::Table(-head=> \@head, 
							-data=> \@data, 
							-align=> "center",
							-border=>1,
							-evenrowclass=>'even',
                            -oddrowclass=>'odd');


$table->print;
#print Dumper(@data);
$dbh->disconnect;
 
 
