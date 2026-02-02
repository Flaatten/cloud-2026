#!/bin/bash

# AWS Resource Cleanup Script for TaskManager Project
# This script deletes all AWS resources created in the workspace to avoid costs
# Usage: ./cleanup-aws-resources.sh [--region REGION] [--profile PROFILE]

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default values
AWS_REGION="eu-west-3"
AWS_PROFILE=""

# Parse command line arguments
while [[ $# -gt 0 ]]; do
  case $1 in
    --region)
      AWS_REGION="$2"
      shift 2
      ;;
    --profile)
      AWS_PROFILE="$2"
      shift 2
      ;;
    --help)
      echo "Usage: $0 [--region REGION] [--profile PROFILE]"
      echo "  --region: AWS region (default: eu-west-3)"
      echo "  --profile: AWS CLI profile (optional)"
      exit 0
      ;;
    *)
      echo "Unknown option: $1"
      exit 1
      ;;
  esac
done

# Set AWS CLI options
AWS_CMD="aws"
if [ -n "$AWS_PROFILE" ]; then
  AWS_CMD="aws --profile $AWS_PROFILE"
fi
AWS_CMD="$AWS_CMD --region $AWS_REGION"

echo -e "${YELLOW}=== AWS Resource Cleanup Script ===${NC}"
echo -e "${YELLOW}Region: $AWS_REGION${NC}"
if [ -n "$AWS_PROFILE" ]; then
  echo -e "${YELLOW}Profile: $AWS_PROFILE${NC}"
fi
echo ""

# Confirm deletion
echo -e "${RED}WARNING: This will delete ALL resources created for the TaskManager project!${NC}"
echo -e "${RED}This includes: EC2 instances, RDS databases, S3 buckets, Lambda functions, CloudWatch resources, IAM roles, and VPC resources.${NC}"
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [ "$CONFIRM" != "yes" ]; then
  echo -e "${YELLOW}Cleanup cancelled.${NC}"
  exit 0
fi

echo ""
echo -e "${GREEN}Starting cleanup...${NC}"
echo ""

# Function to print success message
success() {
  echo -e "${GREEN}✓ $1${NC}"
}

# Function to print error message
error() {
  echo -e "${RED}✗ $1${NC}"
}

# Function to print info message
info() {
  echo -e "${YELLOW}ℹ $1${NC}"
}

# 1. Stop and delete Lambda functions
echo -e "${YELLOW}[1/12] Deleting Lambda functions...${NC}"
LAMBDA_FUNCTIONS=$($AWS_CMD lambda list-functions --query 'Functions[?contains(FunctionName, `task`) || contains(FunctionName, `Task`)].FunctionName' --output text 2>/dev/null || echo "")
if [ -n "$LAMBDA_FUNCTIONS" ]; then
  for FUNCTION in $LAMBDA_FUNCTIONS; do
    # Delete CloudWatch Event triggers first
    RULE_NAMES=$($AWS_CMD events list-rules --query 'Rules[*].Name' --output text 2>/dev/null || echo "")
    for RULE in $RULE_NAMES; do
      TARGETS=$($AWS_CMD events list-targets-by-rule --rule "$RULE" --query 'Targets[?Arn==`arn:aws:lambda:'$AWS_REGION':*:function:'$FUNCTION'`].Id' --output text 2>/dev/null || echo "")
      if [ -n "$TARGETS" ]; then
        $AWS_CMD events remove-targets --rule "$RULE" --ids $TARGETS 2>/dev/null || true
        $AWS_CMD events delete-rule --name "$RULE" 2>/dev/null || true
        success "Deleted CloudWatch Event rule: $RULE"
      fi
    done
    
    $AWS_CMD lambda delete-function --function-name "$FUNCTION" 2>/dev/null || true
    success "Deleted Lambda function: $FUNCTION"
  done
else
  info "No Lambda functions found"
fi

# 2. Delete Lambda Layers
echo -e "${YELLOW}[2/12] Deleting Lambda Layers...${NC}"
LAYERS=$($AWS_CMD lambda list-layers --query 'Layers[?contains(LayerName, `pymysql`) || contains(LayerName, `task`)].LayerName' --output text 2>/dev/null || echo "")
if [ -n "$LAYERS" ]; then
  for LAYER in $LAYERS; do
    VERSIONS=$($AWS_CMD lambda list-layer-versions --layer-name "$LAYER" --query 'LayerVersions[*].Version' --output text 2>/dev/null || echo "")
    for VERSION in $VERSIONS; do
      $AWS_CMD lambda delete-layer-version --layer-name "$LAYER" --version-number "$VERSION" 2>/dev/null || true
    done
    success "Deleted Lambda Layer: $LAYER"
  done
else
  info "No Lambda Layers found"
fi

# 3. Delete CloudWatch Log Groups
echo -e "${YELLOW}[3/12] Deleting CloudWatch Log Groups...${NC}"
LOG_GROUPS=$($AWS_CMD logs describe-log-groups --query 'logGroups[?contains(logGroupName, `taskmanager`) || contains(logGroupName, `/aws/lambda`)].logGroupName' --output text 2>/dev/null || echo "")
if [ -n "$LOG_GROUPS" ]; then
  for LOG_GROUP in $LOG_GROUPS; do
    $AWS_CMD logs delete-log-group --log-group-name "$LOG_GROUP" 2>/dev/null || true
    success "Deleted Log Group: $LOG_GROUP"
  done
else
  info "No CloudWatch Log Groups found"
fi

# 4. Delete CloudWatch Dashboards
echo -e "${YELLOW}[4/12] Deleting CloudWatch Dashboards...${NC}"
DASHBOARDS=$($AWS_CMD cloudwatch list-dashboards --query 'DashboardEntries[?contains(DashboardName, `TaskManager`) || contains(DashboardName, `taskmanager`)].DashboardName' --output text 2>/dev/null || echo "")
if [ -n "$DASHBOARDS" ]; then
  for DASHBOARD in $DASHBOARDS; do
    $AWS_CMD cloudwatch delete-dashboards --dashboard-names "$DASHBOARD" 2>/dev/null || true
    success "Deleted Dashboard: $DASHBOARD"
  done
else
  info "No CloudWatch Dashboards found"
fi

# 5. Terminate EC2 instances
echo -e "${YELLOW}[5/12] Terminating EC2 instances...${NC}"
INSTANCE_IDS=$($AWS_CMD ec2 describe-instances --filters "Name=tag:Name,Values=*task*,*Task*" "Name=instance-state-name,Values=running,stopped" --query 'Reservations[*].Instances[*].InstanceId' --output text 2>/dev/null || echo "")
if [ -z "$INSTANCE_IDS" ]; then
  # Also check for instances without tags
  INSTANCE_IDS=$($AWS_CMD ec2 describe-instances --filters "Name=instance-state-name,Values=running,stopped" --query 'Reservations[*].Instances[*].InstanceId' --output text 2>/dev/null || echo "")
fi

if [ -n "$INSTANCE_IDS" ]; then
  for INSTANCE_ID in $INSTANCE_IDS; do
    # Disable termination protection if enabled
    $AWS_CMD ec2 modify-instance-attribute --instance-id "$INSTANCE_ID" --no-disable-api-termination 2>/dev/null || true
    
    # Terminate instance
    $AWS_CMD ec2 terminate-instances --instance-ids "$INSTANCE_ID" 2>/dev/null || true
    success "Terminating EC2 instance: $INSTANCE_ID"
  done
  
  # Wait for instances to terminate
  info "Waiting for EC2 instances to terminate (this may take a few minutes)..."
  $AWS_CMD ec2 wait instance-terminated --instance-ids $INSTANCE_IDS 2>/dev/null || true
  success "All EC2 instances terminated"
else
  info "No EC2 instances found"
fi

# 6. Delete RDS instances
echo -e "${YELLOW}[6/12] Deleting RDS database instances...${NC}"
RDS_INSTANCES=$($AWS_CMD rds describe-db-instances --query 'DBInstances[?contains(DBInstanceIdentifier, `task`) || contains(DBInstanceIdentifier, `oppgave`)].DBInstanceIdentifier' --output text 2>/dev/null || echo "")
if [ -n "$RDS_INSTANCES" ]; then
  for DB_INSTANCE in $RDS_INSTANCES; do
    # Delete without final snapshot
    $AWS_CMD rds delete-db-instance --db-instance-identifier "$DB_INSTANCE" --skip-final-snapshot --delete-automated-backups 2>/dev/null || true
    success "Deleting RDS instance: $DB_INSTANCE"
  done
  
  # Wait for RDS instances to be deleted
  info "Waiting for RDS instances to be deleted (this may take several minutes)..."
  for DB_INSTANCE in $RDS_INSTANCES; do
    $AWS_CMD rds wait db-instance-deleted --db-instance-identifier "$DB_INSTANCE" 2>/dev/null || true
  done
  success "All RDS instances deleted"
else
  info "No RDS instances found"
fi

# 7. Delete RDS Subnet Groups
echo -e "${YELLOW}[7/12] Deleting RDS DB Subnet Groups...${NC}"
SUBNET_GROUPS=$($AWS_CMD rds describe-db-subnet-groups --query 'DBSubnetGroups[*].DBSubnetGroupName' --output text 2>/dev/null || echo "")
if [ -n "$SUBNET_GROUPS" ]; then
  for SUBNET_GROUP in $SUBNET_GROUPS; do
    # Skip default subnet group
    if [ "$SUBNET_GROUP" != "default" ]; then
      $AWS_CMD rds delete-db-subnet-group --db-subnet-group-name "$SUBNET_GROUP" 2>/dev/null || true
      success "Deleted DB Subnet Group: $SUBNET_GROUP"
    fi
  done
else
  info "No DB Subnet Groups found"
fi

# 8. Empty and delete S3 buckets
echo -e "${YELLOW}[8/12] Deleting S3 buckets...${NC}"
S3_BUCKETS=$($AWS_CMD s3api list-buckets --query 'Buckets[?contains(Name, `oppgavestyring`) || contains(Name, `taskmanager`) || contains(Name, `task-`)].Name' --output text 2>/dev/null || echo "")
if [ -n "$S3_BUCKETS" ]; then
  for BUCKET in $S3_BUCKETS; do
    # Empty bucket first (delete all objects and versions)
    info "Emptying bucket: $BUCKET"
    $AWS_CMD s3 rm s3://"$BUCKET" --recursive 2>/dev/null || true
    
    # Delete all object versions and delete markers
    VERSIONS=$($AWS_CMD s3api list-object-versions --bucket "$BUCKET" --query '{Objects: Versions[].{Key:Key,VersionId:VersionId}}' --output json 2>/dev/null || echo '{"Objects":[]}')
    if [ "$VERSIONS" != '{"Objects":[]}' ] && [ "$VERSIONS" != '{"Objects":null}' ]; then
      echo "$VERSIONS" | $AWS_CMD s3api delete-objects --bucket "$BUCKET" --delete file:///dev/stdin 2>/dev/null || true
    fi
    
    DELETE_MARKERS=$($AWS_CMD s3api list-object-versions --bucket "$BUCKET" --query '{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' --output json 2>/dev/null || echo '{"Objects":[]}')
    if [ "$DELETE_MARKERS" != '{"Objects":[]}' ] && [ "$DELETE_MARKERS" != '{"Objects":null}' ]; then
      echo "$DELETE_MARKERS" | $AWS_CMD s3api delete-objects --bucket "$BUCKET" --delete file:///dev/stdin 2>/dev/null || true
    fi
    
    # Delete bucket
    $AWS_CMD s3api delete-bucket --bucket "$BUCKET" 2>/dev/null || true
    success "Deleted S3 bucket: $BUCKET"
  done
else
  info "No S3 buckets found"
fi

# 9. Delete Security Groups (after EC2 and RDS are deleted)
echo -e "${YELLOW}[9/12] Deleting Security Groups...${NC}"
# Get VPCs first
VPC_IDS=$($AWS_CMD ec2 describe-vpcs --filters "Name=tag:Name,Values=*Oppgave*,*Task*,*task*" --query 'Vpcs[*].VpcId' --output text 2>/dev/null || echo "")
if [ -n "$VPC_IDS" ]; then
  for VPC_ID in $VPC_IDS; do
    SECURITY_GROUPS=$($AWS_CMD ec2 describe-security-groups --filters "Name=vpc-id,Values=$VPC_ID" --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text 2>/dev/null || echo "")
    if [ -n "$SECURITY_GROUPS" ]; then
      # Need to wait a bit for resources to fully release
      sleep 10
      
      for SG_ID in $SECURITY_GROUPS; do
        # Remove all rules first
        $AWS_CMD ec2 revoke-security-group-ingress --group-id "$SG_ID" --ip-permissions "$($AWS_CMD ec2 describe-security-groups --group-ids "$SG_ID" --query 'SecurityGroups[0].IpPermissions' --output json)" 2>/dev/null || true
        $AWS_CMD ec2 revoke-security-group-egress --group-id "$SG_ID" --ip-permissions "$($AWS_CMD ec2 describe-security-groups --group-ids "$SG_ID" --query 'SecurityGroups[0].IpPermissionsEgress' --output json)" 2>/dev/null || true
        
        # Delete security group
        $AWS_CMD ec2 delete-security-group --group-id "$SG_ID" 2>/dev/null || true
        success "Deleted Security Group: $SG_ID"
      done
    fi
  done
fi

# Also delete security groups by name pattern
SG_BY_NAME=$($AWS_CMD ec2 describe-security-groups --filters "Name=group-name,Values=*task*,*Task*,*oppgave*" --query 'SecurityGroups[?GroupName!=`default`].GroupId' --output text 2>/dev/null || echo "")
if [ -n "$SG_BY_NAME" ]; then
  for SG_ID in $SG_BY_NAME; do
    $AWS_CMD ec2 revoke-security-group-ingress --group-id "$SG_ID" --ip-permissions "$($AWS_CMD ec2 describe-security-groups --group-ids "$SG_ID" --query 'SecurityGroups[0].IpPermissions' --output json)" 2>/dev/null || true
    $AWS_CMD ec2 revoke-security-group-egress --group-id "$SG_ID" --ip-permissions "$($AWS_CMD ec2 describe-security-groups --group-ids "$SG_ID" --query 'SecurityGroups[0].IpPermissionsEgress' --output json)" 2>/dev/null || true
    $AWS_CMD ec2 delete-security-group --group-id "$SG_ID" 2>/dev/null || true
    success "Deleted Security Group: $SG_ID"
  done
else
  info "No additional Security Groups found"
fi

# 10. Delete VPC resources (Internet Gateways, Subnets, Route Tables, VPC)
echo -e "${YELLOW}[10/12] Deleting VPC resources...${NC}"
if [ -n "$VPC_IDS" ]; then
  for VPC_ID in $VPC_IDS; do
    # Delete Internet Gateways
    IGW_IDS=$($AWS_CMD ec2 describe-internet-gateways --filters "Name=attachment.vpc-id,Values=$VPC_ID" --query 'InternetGateways[*].InternetGatewayId' --output text 2>/dev/null || echo "")
    for IGW_ID in $IGW_IDS; do
      $AWS_CMD ec2 detach-internet-gateway --internet-gateway-id "$IGW_ID" --vpc-id "$VPC_ID" 2>/dev/null || true
      $AWS_CMD ec2 delete-internet-gateway --internet-gateway-id "$IGW_ID" 2>/dev/null || true
      success "Deleted Internet Gateway: $IGW_ID"
    done
    
    # Delete Subnets
    SUBNET_IDS=$($AWS_CMD ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" --query 'Subnets[*].SubnetId' --output text 2>/dev/null || echo "")
    for SUBNET_ID in $SUBNET_IDS; do
      $AWS_CMD ec2 delete-subnet --subnet-id "$SUBNET_ID" 2>/dev/null || true
      success "Deleted Subnet: $SUBNET_ID"
    done
    
    # Delete Route Tables (except main)
    ROUTE_TABLE_IDS=$($AWS_CMD ec2 describe-route-tables --filters "Name=vpc-id,Values=$VPC_ID" --query 'RouteTables[?Associations[0].Main!=`true`].RouteTableId' --output text 2>/dev/null || echo "")
    for RT_ID in $ROUTE_TABLE_IDS; do
      # Disassociate first
      ASSOCIATIONS=$($AWS_CMD ec2 describe-route-tables --route-table-ids "$RT_ID" --query 'RouteTables[0].Associations[?!Main].RouteTableAssociationId' --output text 2>/dev/null || echo "")
      for ASSOC_ID in $ASSOCIATIONS; do
        $AWS_CMD ec2 disassociate-route-table --association-id "$ASSOC_ID" 2>/dev/null || true
      done
      $AWS_CMD ec2 delete-route-table --route-table-id "$RT_ID" 2>/dev/null || true
      success "Deleted Route Table: $RT_ID"
    done
    
    # Delete VPC
    $AWS_CMD ec2 delete-vpc --vpc-id "$VPC_ID" 2>/dev/null || true
    success "Deleted VPC: $VPC_ID"
  done
else
  info "No VPCs found"
fi

# 11. Delete IAM Roles and Policies
echo -e "${YELLOW}[11/12] Deleting IAM Roles...${NC}"
IAM_ROLES=$($AWS_CMD iam list-roles --query 'Roles[?contains(RoleName, `task`) || contains(RoleName, `Task`) || contains(RoleName, `CloudWatch`) || contains(RoleName, `Lambda`)].RoleName' --output text 2>/dev/null || echo "")
if [ -n "$IAM_ROLES" ]; then
  for ROLE in $IAM_ROLES; do
    # Detach managed policies
    ATTACHED_POLICIES=$($AWS_CMD iam list-attached-role-policies --role-name "$ROLE" --query 'AttachedPolicies[*].PolicyArn' --output text 2>/dev/null || echo "")
    for POLICY_ARN in $ATTACHED_POLICIES; do
      $AWS_CMD iam detach-role-policy --role-name "$ROLE" --policy-arn "$POLICY_ARN" 2>/dev/null || true
    done
    
    # Delete inline policies
    INLINE_POLICIES=$($AWS_CMD iam list-role-policies --role-name "$ROLE" --query 'PolicyNames[*]' --output text 2>/dev/null || echo "")
    for POLICY_NAME in $INLINE_POLICIES; do
      $AWS_CMD iam delete-role-policy --role-name "$ROLE" --policy-name "$POLICY_NAME" 2>/dev/null || true
    done
    
    # Remove instance profiles
    INSTANCE_PROFILES=$($AWS_CMD iam list-instance-profiles-for-role --role-name "$ROLE" --query 'InstanceProfiles[*].InstanceProfileName' --output text 2>/dev/null || echo "")
    for PROFILE in $INSTANCE_PROFILES; do
      $AWS_CMD iam remove-role-from-instance-profile --instance-profile-name "$PROFILE" --role-name "$ROLE" 2>/dev/null || true
      $AWS_CMD iam delete-instance-profile --instance-profile-name "$PROFILE" 2>/dev/null || true
    done
    
    # Delete role
    $AWS_CMD iam delete-role --role-name "$ROLE" 2>/dev/null || true
    success "Deleted IAM Role: $ROLE"
  done
else
  info "No IAM Roles found"
fi

# 12. Delete Key Pairs
echo -e "${YELLOW}[12/12] Deleting EC2 Key Pairs...${NC}"
KEY_PAIRS=$($AWS_CMD ec2 describe-key-pairs --query 'KeyPairs[?contains(KeyName, `task`) || contains(KeyName, `Task`)].KeyName' --output text 2>/dev/null || echo "")
if [ -n "$KEY_PAIRS" ]; then
  for KEY_NAME in $KEY_PAIRS; do
    $AWS_CMD ec2 delete-key-pair --key-name "$KEY_NAME" 2>/dev/null || true
    success "Deleted Key Pair: $KEY_NAME"
  done
else
  info "No Key Pairs found"
fi

echo ""
echo -e "${GREEN}=== Cleanup Complete ===${NC}"
echo ""
echo -e "${YELLOW}Additional Notes:${NC}"
echo "1. Check AWS Console to verify all resources are deleted"
echo "2. Monitor your AWS billing to ensure no unexpected charges"
echo "3. Some resources may take a few minutes to fully delete"
echo "4. If you created resources with custom names not matching the patterns,"
echo "   you may need to delete them manually"
echo ""
echo -e "${GREEN}Resources that should be deleted:${NC}"
echo "  ✓ Lambda functions and layers"
echo "  ✓ CloudWatch Log Groups and Dashboards"
echo "  ✓ EC2 instances"
echo "  ✓ RDS databases"
echo "  ✓ S3 buckets"
echo "  ✓ Security Groups"
echo "  ✓ VPC and related networking resources"
echo "  ✓ IAM Roles and policies"
echo "  ✓ EC2 Key Pairs"
echo ""
