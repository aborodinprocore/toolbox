import boto3
import subprocess
import os
import glob
import time

SUPPORTED_TYPES = ['A', 'AAAA', 'CNAME']
TERRAFORM_FILE = "main.tf"
TEMP_TF_FILE = "temp.tf"

# Check if Terraform files exist and append timestamp if necessary
def check_or_create_tf_file():
    tf_files = glob.glob("*.tf")
    if not tf_files:
        timestamp = str(int(time.time()))
        terraform_file_with_timestamp = f"{timestamp}-{TERRAFORM_FILE}"
        with open(terraform_file_with_timestamp, "w") as f:
            f.write("""terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}
""")
        print(f"{terraform_file_with_timestamp} created.")
        return terraform_file_with_timestamp
    return TERRAFORM_FILE

# Initialize Terraform
def initialize_terraform():
    try:
        subprocess.run(["terraform", "init", "-upgrade"], check=True)
        print("Terraform initialized.")
    except subprocess.CalledProcessError as e:
        print(f"Terraform initialization failed: {e}")
        exit(1)

# Create Terraform Resource Block
def create_terraform_resource(record, hosted_zone_id, terraform_file):
    name = record['Name'].rstrip('.')
    record_type = record['Type']
    identifier = f"{name.replace('.', '_').replace('*', 'star')}_{record_type}"
    
    resource_block = f"""
resource "aws_route53_record" "{identifier}" {{
  zone_id = "{hosted_zone_id}"
  name    = "{name}"
  type    = "{record_type}"
  ttl     = {record['TTL']}
  records = [{", ".join(f'"{r["Value"]}"' for r in record['ResourceRecords'])}]
}}
"""
    with open(terraform_file, "a") as f:
        f.write(resource_block)
        print(f"Added resource {identifier} to {terraform_file}")
    return identifier

# Fetch Route 53 Records
def get_route53_records(hosted_zone_id):
    route53 = boto3.client('route53')
    records = []
    paginator = route53.get_paginator('list_resource_record_sets')
    for page in paginator.paginate(HostedZoneId=hosted_zone_id):
        for record in page['ResourceRecordSets']:
            if record['Type'] in SUPPORTED_TYPES:
                records.append(record)
    return records

# Import Records into Terraform
def import_records(records, hosted_zone_id, terraform_file):
    for record in records:
        identifier = create_terraform_resource(record, hosted_zone_id, terraform_file)
        import_cmd = [
            "terraform", "import",
            f"aws_route53_record.{identifier}",
            f"{hosted_zone_id}_{record['Name'].rstrip('.')}_{record['Type']}"
        ]
        try:
            subprocess.run(import_cmd, check=True)
            print(f"Imported {identifier}")
        except subprocess.CalledProcessError as e:
            print(f"Failed to import {identifier}: {e}")

if __name__ == "__main__":
    hosted_zone_id = input("Enter your AWS Route 53 Hosted Zone ID: ").strip()

    # Create temp.tf with timestamp if needed
    terraform_file = check_or_create_tf_file()

    print("Fetching Route 53 records...")
    records = get_route53_records(hosted_zone_id)

    print("Initializing Terraform...")
    initialize_terraform()

    print("Importing records into Terraform...")
    import_records(records, hosted_zone_id, terraform_file)

    # Clean up temp.tf if created
    if terraform_file != TERRAFORM_FILE and os.path.exists(terraform_file):
        os.remove(terraform_file)
        print(f"{terraform_file} removed.")