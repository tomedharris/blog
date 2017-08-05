---
title: "Hip Laravel development environment with Docker"
date: 2017-08-03
tags: ["php", "docker", "laravel"]
draft: true
---

## Introduction

Docker is cool, there is no doubt about it. It is also my favourite way to build a development environment. Many years ago, I started using Vagrant and Virtual Box to build isolated development environments which imitated my production servers. The main issue for me with Vagrant is that each machine is a full OS which requires resources. Trying to run 2 or more VMs on a laptop can be painful so when working on multiple projects, you end up in a juggling act of provisioning, halting, starting and destroying different machines.

Docker is many things, but as a way to build development environments, it really shines. In this guide, I am going to go through building a development environment for a Laravel project, and some of my work flow. The architecture for the environment will be an apache server, with php 7.1, laravel 5.4, and mysql 5.7.

## Selecting a base image

I don't want to give a Docker tutorial as there are many of varying levels of depth, but you should have a basic understanding of Docker, how it works, and how to interact with it using the cli.

First of all we need to create an image for our apache server. Luckily Docker hub provides many pre made images which we can extend for our use case. The one mistake that a lot of people make with Docker, is they try to create an image that runs the entire stack. Whilst this is technically possible... **DO NOT DO THIS** I cannot emphasise this enough, you lose the majority of Dockers benefits by doing this, and will cause yourself a lot of headaches. The idea is that you create a Docker container for each part of your system. So one container is your web server, another is your database, another is your redis cache. You might use single-use containers to run a single command, for example, building your assets with gulp, or running Laravel artisan commands, or running your test suite with PHPUnit.

If we look at the https://hub.docker.com/_/php/ official PHP repository on DockerHub, we can see that they provide a preconfigured PHP and apache image by looking at the tags section. Firtly, pull this image with: `$ docker pull php:7.1-apache`. Lets start with something simple. Create a test file and run a new container from the image we just downloaded.

```
$ echo "<?php phpinfo();" > index.php

$ docker run --rm -it -v $(pwd):/var/www/html -p 8080:80 php:7.1-apache
```

Now go to http://localhost:8080 in your browser and you should see your PHP Info page. Simple eh?

If you have never used Docker before, the above command might seem a bit, well, complex. They get worse, but once you get your head around Docker, it makes sense. At the end of this article I will introduce docker-compose which helps to set things up using configuration files but it is important to get used to the Docker commands first as you will use them a lot. Here I break down the last command to illustrate what we are telling Docker to do:

`docker run` - The Docker run command, simple enough.

`--rm` - Once the container has finished running (the apache process stops), delete the container.

`-it` - Attach an interactive tty to the running container. This allows us to send keystrokes to the container (e.g. ctrl-c to halt the server).

`-v $(pwd):/var/www/html` - Mount the current working directory to the path /var/www/html on the container, this is where apaches document root is as setup in the php:7.1-apache Docker image.

`-p 8080:80` - Forward port 8080 on our machine, to port 80 (apaches default port) on the container. We could do use 80:80 but the chances are that port 80 on our machine is already in use.

`php:7.1-apache` - Use the image we pulled earlier, specifically, the *php* image using the tag *7.1-apache*.

## Customising the image

The current image is great as a base but it is not setup for our specific use case of running a Laravel project. For starters, the document root points to /var/www/html where as Laravel by default convention uses public as the folder for the publicly accessible root. We also need to enable some apache modules to get everything working. To do this we need to create a custom image which extends php:7.1-apache.

Create a folder for your Docker images somewhere on your computer, I use `/home/tom/Docker Images`. I would keep them separate from your project source code and probably source control them as a separate repository.

Inside this folder create a folder called `laravel`, and inside that create a file called `Dockerfile` and a file called `vhost.conf` like so:

```txt
Docker Images
└── laravel
    ├── Dockerfile
    └── vhost.conf
```

----

Open `vhost.conf` and paste in the following lines:

```
<VirtualHost *:80>
	ServerAdmin webmaster@localhost
	DocumentRoot /app/public

	ErrorLog ${APACHE_LOG_DIR}/error.log
	CustomLog ${APACHE_LOG_DIR}/access.log combined

	<Directory "/app">
		Options Indexes FollowSymLinks
        AllowOverride None
        Require all granted
	</Directory>

	<Directory "/app/public">
		AllowOverride all
	</Directory>
</VirtualHost>
```

----

Open `Dockerfile` and paste in the following lines:

```text
# Extending the php apache image.
FROM php:7.1-apache

# Use our custom apache config.
COPY vhost.conf /etc/apache2/sites-enabled/000-default.conf

# Run the a2enmod command to install mod_rewrite.
RUN a2enmod rewrite

# Change the default directory.
# It is specified as /var/www/html in the base image.
WORKDIR /app
```

----

Now that we have specified alterations to the image we need to build it. Make sure you are in the directory with the Dockerfile, and run the following.

```
$ docker built -t myname/laravel .
```

We can now use our newly created image to host our Laravel app: change directory to your project root and run the following:

```
$ docker run --rm -it -v $(pwd):/app -p 8080:80 myname:laravel
```

Notice that we have change php:7.1-apache for myname:laravel here, this being the new image we created above. We have also changed the volume mount point from /var/www/html to /app. This now means that inside the container the public folder is on the path /app/public, which is as we specified in the vhost.conf.

Visit http://localhost:8080 and you should see your Laravel site. Please note that we haven't setup a database yet so you may see PDO exceptions but we will fix that next. Use Ctrl-C to kill the server.

----

## Creating a database container

Luckily, there are plenty of MySQL images on DockerHub which will do what we need without any modification. Run the following command:

```
$ docker run -d --name myapp-db \ 
  -e MYSQL_ROOT_PASSWORD=password -e MYSQL_DATABASE=laravel \
  mysql:5.7
```

The difference here is we ran docker run with `-d` instead of `--rm -it`. Essentially this means that we are running it as a background process, so instead of seeing the output of the MySQL process we are returned to our shell. If you run `$ docker ps` you will see MySQL with the name 'myapp-db'. We need to configure Laravel to communicate with MySQL but by default Laravel is setup to use localhost.

### Creating a user defined network for our application

Lets use Dockers network features to create a user defined network:

```
$ docker network create --subnet=172.18.0.0/16 myapp
```

### Linking our containers together

We now need to recreate the MySQL container and use our user defined network, we also assign a static IP, but first lets stop and destroy the current running MySQL container:

```
$ docker stop myapp-db && docker rm myapp-db # Or you can just use docker rm -f myapp-db
$ docker run -d --name myapp-db -e MYSQL_ROOT_PASSWORD=password -e MYSQL_DATABASE=laravel --net myapp --ip 172.18.0.22 mysql:5.7
```

Now if you run `$ docker network inspect myapp` you will see 'myapp-db' under the containers section of the output. We now need to tell Laravel where to discover our database, go to your .env file and fill in the DB information.

```
DB_CONNECTION=mysql
DB_HOST=172.18.0.22
DB_PORT=3306
DB_DATABASE=laravel
DB_USERNAME=root
DB_PASSWORD=password
```

We can now re run our Laravel container using the network we created to view our site and now the container will be able to communicate with MySQL. But first lets create an alias for the docker run command to save having to type it in each time. Note that we areadding the `--net myapp` option to the docker run command so that we can communicate with the MySQL container.

```
$ alias myapp="docker run --rm -it -v $(pwd):/app \
  -p 8080:80 --net myapp myname/laravel"
$ myapp # starts the container
```


## Running artisan commands

When we run a docker run command, the image will most likely have a default command. This means that if you don't supply any arguments after the image name, the default will run. If the case of php:7.1-apache (and therefore our image myname/laravel) this is the apache server. If we supply an argument to the command this gets executed instead.

Try running: 

```
$ myapp /bin/bash
```

You will now see that you are using bash inside the container. You can have a poke around here and this is good for debugging containers.  Type `exit` to exit the command. Note that now the container has been destroyed, so don't think that you can make changes using /bin/bash as they are only temporary.

Because the WORKDIR in our Dockerfile is set to /app, any commands we issue after the docker run are run from that working directory. Try `myapp php artisan migrate` and `myapp php artisan db:seed`. What has happened here is that we have created a temporary container using the myname/laravel image, and issued the artisan migrate command. If everything is setup correctly so far you should see you application migrate the database in your MySQL container. The containers process finishes and the container is deleted. This all happens very quickly. *Note: you may need to wait a few minutes after running a fresh MySQL container until you can connect*

It is worth pointing out that if we were to destroy the myapp-db container at this point we lose the data in our database. You can use `docker stop myapp-db` and `docker start myapp-db` to stop and start the container without destroying the disk. You can also use [Docker volumes](https://docs.docker.com/engine/tutorials/dockervolumes/) to manage persistent data if you require this.

# Simplifying things with docker-compose

TODO