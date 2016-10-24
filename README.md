# Departure monitor for FHEM
Departure is a fhem modul, which creates readings for the next departures of a station.

## How to install
The Perl module can be loaded directly into your FHEM installation. For this please copy the below command into the FHEM command line.

	update all https://raw.githubusercontent.com/uniqueck/fhem-departure/develop/controls_fhemdeparture.txt
	
### Create a device
	
	define myDepature Departure 60
	
### Attributes
	

## How to Update
The Perl module can be update directly with standard fhem update process. For this please copy the below command into the FHEM command line.

	update add https://raw.githubusercontent.com/uniqueck/fhem-departure/develop/controls_fhemdeparture.txt

To check if a new version is available execute follow command

	update check fhemdeparture

To update to a new version if available execute follow command

	update all

or

	update all fhemdeparture
