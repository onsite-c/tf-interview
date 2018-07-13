#!/bin/bash

yum update -y
yum install -y httpd
chkconfig httpd on
service httpd start
usermod -a -G apache ec2-user
chown -R ec2-user:apache /var/www
chmod 2775 /var/www
find /var/www -type d -exec chmod 2775 {} \;
find /var/www -type f -exec chmod 0664 {} \;
echo "I am in room Voyager" > /var/www/html/index.html
