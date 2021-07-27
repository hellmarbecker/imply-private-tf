#!/bin/bash
# see https://docs.aws.amazon.com/cli/latest/userguide/cli-configure-quickstart.html#cli-configure-quickstart-region
aws ec2 describe-images \
    --owners amazon \
    --filters "Name=name,Values=amzn2-ami-hvm-2.0.????????.?-x86_64-gp2" "Name=state,Values=available" \
    --query "reverse(sort_by(Images, &Name))[:1].ImageId" \
    --output text \
    --region eu-central-1
