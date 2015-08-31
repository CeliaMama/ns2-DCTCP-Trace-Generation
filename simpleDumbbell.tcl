set N 4
set B 4000
set K 2000

set RTT 0.04

set simulationTime 50.0

set startMeasurementTime 0.0
set stopMeasurementTime 50.0
set flowClassifyTime 0.04

set sourceAlg DC-TCP-Sack
#set sourceAlg DC-TCP-Newreno
#set sourceAlg DC-TCP-Cubic
set switchAlg RED
set lineRate 1.1Gb
set inputLineRate 1Gb

set DCTCP_g_ 0.0625
set ackRatio 1 
set packetSize 1460
 
#set traceSamplingInterval 0.0001
set traceSamplingInterval 0.0001
set throughputSamplingInterval 0.01
set enableNAM 0
set ns [new Simulator]

Agent/TCP set ecn_ 1
Agent/TCP set old_ecn_ 1
Agent/TCP set packetSize_ $packetSize
Agent/TCP/FullTcp set segsize_ $packetSize
Agent/TCP set window_ 4000
Agent/TCP set slow_start_restart_ false
Agent/TCP set tcpTick_ 0.01
Agent/TCP set minrto_ 0.2 ; # minRTO = 200ms
Agent/TCP set windowOption_ 0


if {[string compare $sourceAlg "DC-TCP-Sack"] == 0} {
    Agent/TCP set dctcp_ true
    Agent/TCP set dctcp_g_ $DCTCP_g_
    Trace set show_tcphdr_ 1
}
Agent/TCP/FullTcp set segsperack_ $ackRatio; 
Agent/TCP/FullTcp set spa_thresh_ 3000;
Agent/TCP/FullTcp set interval_ 0.04 ; #delayed ACK interval = 40ms

Queue set limit_ 1000

Queue/RED set bytes_ false
Queue/RED set queue_in_bytes_ true
Queue/RED set mean_pktsize_ $packetSize
Queue/RED set setbit_ true
Queue/RED set gentle_ false
Queue/RED set q_weight_ 1.0
Queue/RED set mark_p_ 1.0
Queue/RED set thresh_ [expr $K]
Queue/RED set maxthresh_ [expr $K]
             
DelayLink set avoidReordering_ true

if {$enableNAM != 0} {
    set namfile [open outDCTCP40ms4nodes.nam w]
    $ns namtrace-all $namfile
}

set mytracefile [open mytracefileDCTCP40ms4nodes.tr w]
set throughputfile [open thrfileDCTCP40ms4nodes.tr w]
#Open the Trace file
set tf [open outDCTCP40ms4nodes.tr w]
$ns trace-all $tf

proc finish {} {
        global ns enableNAM namfile mytracefile throughputfile tf
        $ns flush-trace
        close $mytracefile
        close $throughputfile
        close $tf
        if {$enableNAM != 0} {
        close $namfile
        exec nam outDCTCP40ms4nodes.nam &
    }
    exit 0
}

proc myTrace {file} {
    global ns N traceSamplingInterval tcp qfile MainLink nbow nclient packetSize enableBumpOnWire
    
    set now [$ns now]
    
    for {set i 0} {$i < $N} {incr i} {
    set cwnd($i) [$tcp($i) set cwnd_]
    set dctcp_alpha($i) [$tcp($i) set dctcp_alpha_]
    }
    
    $qfile instvar parrivals_ pdepartures_ pdrops_ bdepartures_
  
    puts -nonewline $file "$now $cwnd(0)"
    for {set i 1} {$i < $N} {incr i} {
    puts -nonewline $file " $cwnd($i)"
    }
    for {set i 0} {$i < $N} {incr i} {
    puts -nonewline $file " $dctcp_alpha($i)"
    }
 
    puts -nonewline $file " [expr $parrivals_-$pdepartures_-$pdrops_]"    
    puts $file " $pdrops_"
     
    $ns at [expr $now+$traceSamplingInterval] "myTrace $file"
}

proc throughputTrace {file} {
    global ns throughputSamplingInterval qfile flowstats N flowClassifyTime
    
    set now [$ns now]
    
    $qfile instvar bdepartures_
    
    puts -nonewline $file "$now [expr $bdepartures_*8/$throughputSamplingInterval/1000000]"
    set bdepartures_ 0
    if {$now <= $flowClassifyTime} {
    for {set i 0} {$i < [expr $N-1]} {incr i} {
        puts -nonewline $file " 0"
    }
    puts $file " 0"
    }

    if {$now > $flowClassifyTime} { 
    for {set i 0} {$i < [expr $N-1]} {incr i} {
        $flowstats($i) instvar barrivals_
        puts -nonewline $file " [expr $barrivals_*8/$throughputSamplingInterval/1000000]"
        set barrivals_ 0
    }
    $flowstats([expr $N-1]) instvar barrivals_
    puts $file " [expr $barrivals_*8/$throughputSamplingInterval/1000000]"
    set barrivals_ 0
    }
    $ns at [expr $now+$throughputSamplingInterval] "throughputTrace $file"
}


$ns color 0 Red
$ns color 1 Orange
$ns color 2 Yellow
$ns color 3 Green
$ns color 4 Blue
$ns color 5 Violet
$ns color 6 Brown
$ns color 7 Black

for {set i 0} {$i < $N} {incr i} {
    set n($i) [$ns node]
}

set nqueue [$ns node]
set nclient [$ns node]


$nqueue color red
$nqueue shape box
$nclient color blue

for {set i 0} {$i < $N} {incr i} {
    $ns duplex-link $n($i) $nqueue $inputLineRate [expr $RTT/4] DropTail
    $ns duplex-link-op $n($i) $nqueue queuePos 0.25
}


$ns simplex-link $nqueue $nclient $lineRate [expr $RTT/4] $switchAlg
$ns simplex-link $nclient $nqueue $lineRate [expr $RTT/4] DropTail
$ns queue-limit $nqueue $nclient $B

$ns duplex-link-op $nqueue $nclient color "green"
$ns duplex-link-op $nqueue $nclient queuePos 0.25
set qfile [$ns monitor-queue $nqueue $nclient [open queue.tr w] $traceSamplingInterval]

#Create the error model
set tmp [new ErrorModel/Uniform 0 pkt] 
set tmp1 [new ErrorModel/Uniform 1 pkt]

# Array of states (error models)
set m_states [list $tmp $tmp1]
# Durations for each of the states, tmp, tmp1 and tmp2, respectively 
#set m_periods [list 0.2 0.1 0.05]
set m_periods [list 4 0.01]
# Transition state model matrix
#set m_transmx { {0 1 0}
#{0 0 1}
#{1 0 0}}
set m_transmx { {0 1}
{1 0}}
set m_trunit pkt
# Use time-based transition
set m_sttype time
set m_nstates 2
set m_nstart [lindex $m_states 0]
set em [new ErrorModel/MultiState $m_states $m_periods $m_transmx $m_trunit $m_sttype $m_nstates $m_nstart]

#$ns link-lossmodel $em $nqueue $nclient

for {set i 0} {$i < $N} {incr i} {
    if {[string compare $sourceAlg "Newreno"] == 0 || [string compare $sourceAlg "DC-TCP-Newreno"] == 0} {
        set tcp($i) [new Agent/TCP/Newreno]
        set sink($i) [new Agent/TCPSink]
    }
    if {[string compare $sourceAlg "Sack"] == 0 || [string compare $sourceAlg "DC-TCP-Sack"] == 0} { 
        set tcp($i) [new Agent/TCP/FullTcp]
        set sink($i) [new Agent/TCP/FullTcp]
        #set sink($i) [new Agent/TCPSink/DelAck]
        $sink($i) listen
    }
    if {[string compare $sourceAlg "Cubic"] == 0 || [string compare $sourceAlg "DC-TCP-Cubic"] == 0} {
        set tcp($i) [new Agent/TCP/Linux]
        $tcp($i) set timestamps_ true
        # $tcp($i) set windowOption_ 1000
        $ns at 0 "$tcp($i) select_ca cubic"
        #$tcp($i) select_ca cubic
        #set sink($i) [new Agent/TCPSink/Sack1/DelAck]
        set sink($i) [new Agent/TCPSink]
        #$sink($i) set ts_echo_rfc1323_ true
        #set sink($i) [new Agent/TCPSink/DelAck]
    }

    $ns attach-agent $n($i) $tcp($i)
    $ns attach-agent $nclient $sink($i)
    
    $tcp($i) set fid_ [expr $i]
    $sink($i) set fid_ [expr $i]

    $ns connect $tcp($i) $sink($i)       
}

for {set i 0} {$i < $N} {incr i} {
    set ftp($i) [new Application/FTP]
    $ftp($i) attach-agent $tcp($i)    
}
$ns at $traceSamplingInterval "myTrace $mytracefile"
$ns at $throughputSamplingInterval "throughputTrace $throughputfile"

set ru [new RandomVariable/Uniform]
$ru set min_ 0
$ru set max_ 1.0

for {set i 0} {$i < $N} {incr i} {
    #$ns at 0.0 "$ftp($i) send 10000"
    #$ns at [expr 0.1 + $simulationTime * $i / ($N + 0.0001)] "$ftp($i) start"
    $ns at 0.0 "$ftp($i) start"     
    $ns at [expr $simulationTime] "$ftp($i) stop"
}

set flowmon [$ns makeflowmon Fid]
set MainLink [$ns link $nqueue $nclient]

$ns attach-fmon $MainLink $flowmon

set fcl [$flowmon classifier]

$ns at $flowClassifyTime "classifyFlows"

proc classifyFlows {} {
    global N fcl flowstats
    puts "NOW CLASSIFYING FLOWS"
    for {set i 0} {$i < $N} {incr i} {
    set flowstats($i) [$fcl lookup autp 0 0 $i]
    }
} 


set startPacketCount 0
set stopPacketCount 0

proc startMeasurement {} {
global qfile startPacketCount
$qfile instvar pdepartures_   
set startPacketCount $pdepartures_
}

proc stopMeasurement {} {
global qfile startPacketCount stopPacketCount packetSize startMeasurementTime stopMeasurementTime simulationTime
$qfile instvar pdepartures_   
set stopPacketCount $pdepartures_
puts "Throughput = [expr ($stopPacketCount-$startPacketCount)/(1000000*($stopMeasurementTime-$startMeasurementTime))*$packetSize*8] Mbps"
}

$ns at $startMeasurementTime "startMeasurement"
$ns at $stopMeasurementTime "stopMeasurement"
                      
$ns at $simulationTime "finish"

$ns run