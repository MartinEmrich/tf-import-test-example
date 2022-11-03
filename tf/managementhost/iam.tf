
resource "aws_iam_policy" "management_host" {
  name   = "${var.platform_name}-ManagementHostPolicy"
  policy = <<-EOT
    {
      "Version": "2012-10-17",
      "Statement": [
          {
              "Sid": "VisualEditor1",
              "Effect": "Allow",
              "Action": [
                  "ec2:DescribeInstances",
                  "ec2:DescribeTags"
              ],
              "Resource": "*"
          }
      ]
    }
  EOT
}

resource "aws_iam_role" "management_host" {
  path = "/"
  managed_policy_arns = [
    aws_iam_policy.management_host.id,
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore"
  ]
  assume_role_policy = <<-EOT
    {
      "Version": "2012-10-17",
      "Statement": [
        {
          "Effect": "Allow",
          "Principal": {
            "Service": [
              "ec2.amazonaws.com"
            ]
          },
          "Action": [
            "sts:AssumeRole"
          ]
        }
      ]
    }
  EOT
}

resource "aws_iam_instance_profile" "management_host" {
  path = "/"
  role = aws_iam_role.management_host.id
}
