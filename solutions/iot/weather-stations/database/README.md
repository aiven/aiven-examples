# PostgreSQL database for weather station metadata

Run ```import-stations.sh``` script to download metadata from Digitraffic. Script will create PostgreSQL tables and then load data from downloaded JSON files. Uses jq for transformations.
