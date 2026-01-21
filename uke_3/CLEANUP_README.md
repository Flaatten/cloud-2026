# AWS Resource Cleanup

This directory contains a comprehensive cleanup script to delete all AWS resources created during the TaskManager project exercises.

## What Gets Deleted

The script will delete the following AWS resources:

1. **Lambda Functions** - All Lambda functions related to the task management system
2. **Lambda Layers** - PyMySQL and other custom layers
3. **CloudWatch Resources**
   - Log Groups (taskmanager-logs, Lambda logs)
   - Dashboards (TaskManager-Dashboard)
   - Custom Metrics (TaskManagerMetrics namespace)
   - Event Rules (scheduled triggers)
4. **EC2 Instances** - All instances created for the project
5. **RDS Databases** - MySQL database instances
6. **RDS Subnet Groups** - Database subnet groups
7. **S3 Buckets** - Storage buckets (including all objects)
8. **Security Groups** - Custom security groups (default groups are preserved)
9. **VPC Resources**
   - Internet Gateways
   - Subnets
   - Route Tables
   - VPCs
10. **IAM Roles** - CloudWatch and Lambda execution roles
11. **EC2 Key Pairs** - SSH key pairs

## Prerequisites

- AWS CLI installed and configured
- Appropriate AWS credentials with permissions to delete resources
- The AWS resources were created following the workspace exercises

## Usage

### Basic Usage

```bash
./cleanup-aws-resources.sh
```

### With Specific Region

```bash
./cleanup-aws-resources.sh --region eu-west-1
```

### With AWS Profile

```bash
./cleanup-aws-resources.sh --profile gokstad
```

### Combined Options

```bash
./cleanup-aws-resources.sh --region eu-west-1 --profile gokstad
```

### Help

```bash
./cleanup-aws-resources.sh --help
```

## Important Notes

⚠️ **WARNING**: This script will **permanently delete** all resources. Make sure you:

1. Have backups of any important data
2. Are absolutely certain you want to delete these resources
3. Understand that this action cannot be undone

## Resource Naming Patterns

The script identifies resources using these patterns:
- Resources containing "task" or "Task"
- Resources containing "oppgave" or "Oppgave"
- Resources named "taskmanager" or "TaskManager"

If you used custom naming conventions, you may need to:
1. Modify the script to match your patterns, OR
2. Manually delete those resources through the AWS Console

## Execution Time

The cleanup process typically takes 5-15 minutes depending on:
- Number of resources created
- EC2 instance termination time
- RDS database deletion time (can take several minutes)

## Verification

After running the script, verify deletion in the AWS Console:

1. **EC2 Dashboard** - Check for terminated instances
2. **RDS** - Verify database instances are deleted
3. **S3** - Ensure buckets are removed
4. **VPC** - Confirm VPC and related resources are gone
5. **IAM** - Check that custom roles are deleted
6. **CloudWatch** - Verify log groups and dashboards removed
7. **Lambda** - Ensure functions and layers deleted

## Cost Monitoring

After cleanup:
- Check AWS Billing Dashboard after 24 hours
- Verify no ongoing charges
- Some charges may appear for partial usage before deletion

## Troubleshooting

### Script Fails to Delete Resources

1. **Permission Issues**: Ensure your AWS credentials have sufficient permissions
2. **Dependencies**: Some resources depend on others (e.g., can't delete VPC while EC2 running)
   - The script handles this automatically by deleting in proper order
   - If issues persist, wait a few minutes and run again
3. **Region Mismatch**: Ensure you're targeting the correct region

### Resources Not Found

- This is normal if resources were already deleted or never created
- The script will continue with remaining resources

### Manual Deletion Required

Some resources may need manual deletion:
1. Go to AWS Console
2. Navigate to the specific service
3. Select and delete the resource
4. Common services: EC2, RDS, S3, VPC, IAM

## Support

If you encounter issues:
1. Check the AWS CloudTrail logs for detailed error messages
2. Verify your AWS CLI configuration: `aws configure list`
3. Test AWS access: `aws sts get-caller-identity`
4. Review the script output for specific error messages

## Alternative: Manual Deletion

If you prefer to delete resources manually:

1. **EC2 Console**: Terminate instances
2. **RDS Console**: Delete database (skip final snapshot)
3. **S3 Console**: Empty and delete buckets
4. **VPC Console**: Delete VPC (will cascade delete subnets, route tables, etc.)
5. **IAM Console**: Delete custom roles
6. **CloudWatch Console**: Delete log groups and dashboards
7. **Lambda Console**: Delete functions and layers

## Safety Features

The script includes:
- Confirmation prompt before deletion
- Color-coded output for easy tracking
- Graceful error handling (continues on individual failures)
- Waits for long-running operations (EC2/RDS termination)
- Skips default resources (e.g., default security groups)

## License

This script is provided as-is for educational purposes.
