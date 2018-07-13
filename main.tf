# Specify the provider and access details
provider "aws" {
  region  = "us-east-1"
  profile = "interviewprofile"
}

# Create a VPC to launch our instances into
resource "aws_vpc" "interview-vpc" {
  cidr_block = "10.0.0.0/16"

  tags {
    Name = "interview-vpc"
  }
}

# Create an internet gateway to give our subnet access to the outside world
resource "aws_internet_gateway" "default" {
  vpc_id = "${aws_vpc.interview-vpc.id}"
}

# Grant the VPC internet access on its main route table
resource "aws_route" "internet_access" {
  route_table_id         = "${aws_vpc.interview-vpc.main_route_table_id}"
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = "${aws_internet_gateway.default.id}"
}

# Create a subnet to launch our instances into
resource "aws_subnet" "default" {
  vpc_id                  = "${aws_vpc.interview-vpc.id}"
  cidr_block              = "10.0.1.0/24"
  map_public_ip_on_launch = true
}

# A security group for the ELB so it is accessible via the web
resource "aws_security_group" "elb" {
  name        = "terraform_example_elb"
  description = "Used in the terraform"
  vpc_id      = "${aws_vpc.interview-vpc.id}"

  # HTTP access from anywhere
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Our default security group to access
# the instances over SSH and HTTP
resource "aws_security_group" "default" {
  name        = "terraform_example"
  description = "Used in the terraform"
  vpc_id      = "${aws_vpc.interview-vpc.id}"

  # SSH access from anywhere
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTP access from the VPC
  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["${aws_vpc.interview-vpc.cidr_block}"]
  }

  # outbound internet access
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_key_pair" "auth" {
  key_name   = "interview-key"
  public_key = "${file(var.public_key_path)}"
}

data "aws_ami" "amazon-linux" {
  most_recent = true

  filter {
    name   = "name"
    values = ["amzn-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }

  owners = ["137112412989"] # Amazon - us-east-1
}

data "template_file" "init" {
  template = "${file("init.tpl")}"

  vars {
    ROOM_PARAM = "Voyager"
  }
}

resource "aws_launch_template" "launch-template" {
  name_prefix            = "interview"
  image_id               = "${data.aws_ami.amazon-linux.id}"
  instance_type          = "t2.micro"
  vpc_security_group_ids = ["${aws_security_group.default.id}"]
  key_name               = "${aws_key_pair.auth.id}"

  user_data = "${base64encode(data.template_file.init.rendered)}"
}

resource "aws_autoscaling_group" "bar" {
  name = "interview-asg"

  availability_zones  = ["${aws_subnet.default.availability_zone}"]
  vpc_zone_identifier = ["${aws_subnet.default.id}"]

  desired_capacity          = 1
  max_size                  = 1
  min_size                  = 1
  health_check_grace_period = 600
  health_check_type         = "ELB"

  load_balancers = ["${aws_elb.bar.name}"]

  launch_template = {
    id      = "${aws_launch_template.launch-template.id}"
    version = "$$Latest"
  }

  timeouts {
    delete = "15m"
  }
}

resource "aws_elb" "bar" {
  name    = "foobar-terraform-elb"
  subnets = ["${aws_subnet.default.id}"]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  health_check {
    healthy_threshold   = 2
    unhealthy_threshold = 2
    timeout             = 3
    target              = "HTTP:80/"
    interval            = 30
  }

  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  security_groups = ["${aws_security_group.elb.id}"]

  tags {
    Name = "foobar-terraform-elb"
  }
}
