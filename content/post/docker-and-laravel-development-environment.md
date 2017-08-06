---
title: "Docker and Laravel for a hip development environment"
date: 2017-08-06
tags: ["php", "docker", "laravel"]
draft: false
---

## Introduction

Docker is an actual thing, there is no doubt about it. I think one of the hardest jobs of a developer these days is trying to sift the worthwhile technologies from the hype. Many years ago, I started using Vagrant and Virtual Box to build isolated development environments which imitated production servers. A sticking point with Vagrant is that each machine is a full OS; trying to run 2 or more VMs on a laptop can be painful so when working on multiple projects, you end up juggling different machines, provisioning and destroying, halting and starting.

Docker is many things, but as a way to build development environments, it really shines. In this guide, I am going to go through building a development environment for a Laravel project, and some of my work flow. The architecture for the environment will be an apache server, with php 7.1, laravel 5.4, and mysql 5.7.

## Selecting a base image

First of all, we need to create an image for our apache server. If we look at the [official PHP repository on DockerHub](https://hub.docker.com/_/php/), we can see that they provide a preconfigured PHP and apache image. Pull this image with: `$ docker pull php:7.1-apache`. Now create a test file and run a new container from the image we just downloaded.

```
$ echo "<?php phpinfo();" > index.php

$ docker run --rm -it -v $(pwd):/var/www/html -p 8080:80 php:7.1-apache
```

Now go to http://localhost:8080 in your browser and you should see your PHP Info page. Simple eh?

If you have never used Docker before, the above command might seem a bit, convoluted. They get worse, but once you get your head around Docker, it makes sense. At the end of this article I will introduce docker-compose which uses configuration files to build and run your containers. It simplifies things a lot but to be able to work with docker-compose, you need to understand docker.

Let's break down the docker run command into parts to explain what we are doing:

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

Notice we have specified '/app/public as the document root. This means that if we mount our project files at the path '/app', everything should be in the correct place.

Open `Dockerfile` and paste the following lines:

```text
# Extending the php apache image.
FROM php:7.1-apache

# Use our custom apache config.
COPY vhost.conf /etc/apache2/sites-enabled/000-default.conf

# Run the a2enmod command to install mod_rewrite.
RUN a2enmod rewrite

# Install php extensions.
RUN docker-php-ext-install mysqli
RUN docker-php-ext-install pdo_mysql

# Change the default directory.
# It is specified as /var/www/html in the base image.
WORKDIR /app
```

Now that we have specified our alterations to the image, we need to build it. Make sure you are in the directory with the Dockerfile and run:

```
$ docker built -t myname/laravel .
```

Give it a few seconds to run, then once it has built we can use this newly created image to host our Laravel app: change directory to your project root and run the following:

```
$ docker run --rm -it -v $(pwd):/app -p 8080:80 myname:laravel
```

Notice that we have switched 'php:7.1-apache' for our new image, 'myname:laravel' in that last run command. We have also changed the volume mount point from /var/www/html to /app as specified in the vhost.conf.

Visit http://localhost:8080 and you should see your Laravel site. Please note that we haven't setup a database yet so you may see PDO exceptions but we will fix that next. Use Ctrl-C to kill the server.

----

## Creating a database container

Luckily, there are plenty of MySQL images on DockerHub which will do what we need without any modification. Run the following command:

```
$ docker run -d --name myapp-db \ 
  -e MYSQL_ROOT_PASSWORD=password -e MYSQL_DATABASE=laravel \
  mysql:5.7
```

The difference here is we ran docker run with `-d` instead of `--rm -it`. Essentially this means that we are running it as a background process, so instead of seeing the output of the MySQL process we are returned to our shell. If you run `$ docker ps` you will see our MySQL container with the name 'myapp-db'. We need to configure Laravel to communicate with MySQL but by default, Laravel is setup to use localhost.

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

We can now re run our Laravel container using the network we created to view our site and now the container will be able to communicate with MySQL. Note that we are adding the `--net myapp` option to the docker run command so that we can communicate with the MySQL container.

```
$ docker run --rm -it -v $(pwd):/app -p 8080:80 --net myapp myname/laravel
```

----

## Running artisan commands

When we run a docker run command, the image will most likely have a default command. This means that if you don't supply any arguments after the image name, the default will run. If the case of php:7.1-apache (and therefore our image myname/laravel) this is the apache server. If we supply an argument to the command this gets executed instead. This isn't strictly true in all cases as there is a difference between a command and an entry point but that is beyond the scope of this post; for the example here, it works. Try running: 

```
$ docker run --rm -it -v $(pwd):/app --net myapp myname/laravel php artisan migrate
```

Lets break this command down:

`docker run --rm -it -v $(pwd):/app` - Hopefully we understand this at this point.

`--net myapp` - add this container to the myapp network.

`myname/laravel` - Use the image we built.

`php artisan migrate` - Everything after the image name is sent to the container as the command. Since the working directory is /app we can use php artisan migrate to migrate the database.

Please not that this wouldn't work without the `--net ...` option as artisan wouldn't be able to comminicate the the database to perform the migrations. Also, you might have noticed that we didn't forward port 8080:80 with this container, there was no need as we never intend web traffic to hit this container, we are purely using the php-cli provided by the image.

If you wanted to make running artisan commands easier, you could easily create an alias. I usually do something like `$ alias artisan="docker run --rm -it -v $(pwd):/app --net myapp myname/laravel php artisan migrate"`. Now artisan commands can be run using `$ artisan migrate`.

You can also do things like:

```
$ alias phpunit="docker run docker run --rm -it -v $(pwd):/app myname/laravel vendor/bin/phpunit"
$ phpunit
```

----

## Simplifying things with docker-compose

Docker commands can seem a bit complex at first. Thankfully we can use docker-compose to setup and run the containers using a configuration file, but first lets start from scratch by removing the containers we have created. `$ docker rm -f $(docker ps -aq)`. This will remove every docker container.

Create a file `docker-compose.yml`. If you don't want to add it to your repository, place it in the parent directory of your laravel install, and change the paths accordingly, or add it to your .gitignore file.

Add the following to your `docker-composer.yml`

```
version: "2"
services:
  web:
    build: ../Docker Images/laravel
    volumes:
      - .:/app
    ports:
      - "8080:80"
    depends_on:
      - db
  db:
    image: mysql:5.7
    environment:
      - MYSQL_ROOT_PASSWORD=password
      - MYSQL_DATABASE=laravel
```

Now run `$ docker-compose -p myapp -d up`. It will do everything for you including building the image, and running the containers. We can use `$ docker-compose -p myappp down` to drop the the applications.

The problem here is that you will lose all data in your database everytime you run the docker-compose down command. This is because the container is destroyed so the volumes are garbage collected. If you want to persist your database between these runs you will need to make use of docker volumes. The simplest way is to mount a volume into the db: section of the docker-compose.yml file, by mounting a file from your host filesystem, you will always persist that data directory. For example, 

```
# ...
  db:
    # ...
    volumes:
      - /path/to/datadir:/var/lib/mysql

```

There are more elegant solutions that you can learn about by looking at the documentation for [Docker volumes](https://docs.docker.com/engine/tutorials/dockervolumes/).

----

## Conclusion

If you made it to the end of this post, you should now have a development environment consisting of an apache webserver with PHP, and MySQL. Using the techniques used here you could easily add a Redis cache container, or make use of a gulp container as part of your asset building process. The next level is where you can use Docker as your production environment, this really is Dockers raison d'être, being able to package up environments and ships them around like you do with source code.

I hope my first blog post was informative, if there are any errors with my post, please let me know and I will correct them and give credit where I can.
