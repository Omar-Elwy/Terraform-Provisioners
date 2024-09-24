// NOT RECOMMENDED TO USE PROVISIONERS
// ITS ONLY A WORKAROUND

provider "aws" {
    region = "eu-west-3"
}

variable vpc_cidr_block {}
variable subnet_cidr_block {}
variable avail_zone {}
variable env_prefix {}
variable my_ip {}
variable instance_type {}
variable public_key_location {}
variable private_key_location {}

resource "aws_vpc" "myapp-vpc" {
    cidr_block = var.vpc_cidr_block
    tags = {
        Name: "${var.env_prefix}-vpc"
    }
}

resource "aws_subnet" "myapp-subnet-1" {
    vpc_id = aws_vpc.myapp-vpc.id
    cidr_block = var.subnet_cidr_block
    availability_zone = var.avail_zone
    tags = {
        Name: "${var.env_prefix}-subnet-1"
    }
}

resource "aws_internet_gateway" "myapp-igw" {
    vpc_id = aws_vpc.myapp-vpc.id
    tags = {
        Name: "${var.env_prefix}-igw"
    }
}

resource "aws_default_route_table" "main-rtb" {
    default_route_table_id = aws_vpc.myapp-vpc.default_route_table_id

    route {
        cidr_block = "0.0.0.0/0"
        gateway_id = aws_internet_gateway.myapp-igw.id
    }
    tags = {
        Name: "${var.env_prefix}-main-rtb"
    }
}

resource "aws_default_security_group" "default-sg" {
    vpc_id = aws_vpc.myapp-vpc.id

    ingress {
        from_port = 22
        to_port = 22
        protocol = "tcp"
        cidr_blocks = [var.my_ip]
    }

    ingress {
        from_port = 8080
        to_port = 8080
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    egress {
        from_port = 0
        to_port = 0
        protocol = "-1"
        cidr_blocks = ["0.0.0.0/0"]
        prefix_list_ids = []
    }

    tags = {
        Name: "${var.env_prefix}-default-sg"
    }
}

data "aws_ami" "latest-amazon-linux-image" {
    most_recent = true
    owners = ["amazon"]
    filter {
        name = "name"
        values = ["amzn2-ami-hvm-*-x86_64-gp2"]
    }
    filter {
        name = "virtualization-type"
        values = ["hvm"]
    }
}

output "aws_ami_id" {
    value = data.aws_ami.latest-amazon-linux-image.id
}

output "ec2_public_ip" {
    value = aws_instance.myapp-server.public_ip
}

resource "aws_key_pair" "ssh-key" {
    key_name = "server-key"
    public_key = file(var.public_key_location)
}

resource "aws_instance" "myapp-server" {
    ami = data.aws_ami.latest-amazon-linux-image.id
    instance_type = var.instance_type

    subnet_id = aws_subnet.myapp-subnet-1.id
    vpc_security_group_ids = [aws_default_security_group.default-sg.id]
    availability_zone = var.avail_zone

    associate_public_ip_address = true
    key_name = aws_key_pair.ssh-key.key_name

    # user_data = file("entry-script.sh")
    
// We have to define the connection explictly to in order for provisioner to connect ot the server
// Even though we type it inside the server resource like here..    
// Used for both ( file & remote-exec )
    connection {
        type = "ssh"
        // self : refers to the currnet context we are in ( server resouce ) so it address its object..
        host = self.public_ip
        user = "ec2-user"
                          // private_key_location : Our local private key .ssh/id_rsa
        private_key = file(var.private_key_location)
    }
// To copy this file (entry-script.sh) to the remote server to be able to execute it there
    provisioner "file" {
        source = "entry-script.sh"
        // Absolute path on th remote server.
        destination = "/home/ec2-user/entry-script-on-ec2.sh"
    }
// remote-exec : allows us to connect to the remote server and execute commands on it not on local machine..
// So we have to copy this file (entry-script.sh) to the remote server to be able to execute it there (using file provisioner)..
    provisioner "remote-exec" {
        script = file("entry-script.sh")
    }
// local-exec : execute commands on our local machine..
    provisioner "local-exec" {
        command = "echo ${self.public_ip} > output.txt"
    }

    tags = {
        Name = "${var.env_prefix}-server"
    }
}
