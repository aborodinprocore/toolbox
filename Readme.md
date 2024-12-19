This is just a Toolbox

import_dns_ecords.py -  the script will query all the route53 records and import them to one main.tf file. The script needs AWS hosted zone id, to search for the records in it. Also, it creates the tfsate files, so if you run it second time, make sure to delete the state files or it will not be able to import because of the duplicate reaources. 
Preconditions: Boto3 is installed:
pip3 install boto3

