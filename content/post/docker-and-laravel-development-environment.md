---
title: "Docker and Laravel development environment 2018"
date: 2018-06-26
tags: ["php", "docker", "laravel", "devops"]
draft: false
---

## Introduction

This article is an updated version of one [I wrote last year](/archive/docker-and-laravel-development-environment). 
It makes more of an emphasis on using docker-compose and so should be easier to get stated with. It also makes use of Nginx and PHP-FPM as opposed to Apache with mod_php. This will help in a future article when we explore setting up multiple project backend containers, all running through a common Nginx webserver container.

### Who is this article for?

Developers, technical managers, people interested in Docker and devops.

I would recommend a good knowledge of Docker before starting this. Docker is a powerful tool, it also has a fairly steep learning curve. I will try to explain everything as I go, but you might do well to have an understanding of the following before starting:

- How to [run containers](https://docs.docker.com/engine/reference/run/) (`docker run ...`)
- What a container registry is (for example [Docker Hub](https://hub.docker.com))
- What a [Dockerfile](https://docs.docker.com/develop/develop-images/dockerfile_best-practices/) is and how to use a Dockerfile to build images
- How to [tag](https://docs.docker.com/engine/reference/commandline/tag/) images to differentiate versions
- The [docker-compose](https://docs.docker.com/compose/) tool

You might also like to create an account on Docker Hub. This isn't required as you can just store the container images on your machine, and you can pull public images without an account.

### Why Docker?

<a href="https://www.docker.com">
<img src="/images/docker-and-laravel-development-environment/mono-horizontal.png" style="float: right;"/>
</a>

There are numerous advantages of using Docker over other solutions such as Vagrant, or LAMP/WAMP. I won't go into detail but here are a few benefits:

<div style="clear: both;"></div>

- Easily reproduce your application runtime between developers, teams, and even into staging and production. No more, "That's odd, it works on my machine!"
- Lightweight and fast - no more `vagrant up` then go and make a cup of coffee. Also, containers don't use anywhere near as many system resources as a VM (disk, memory, CPU).
- If one project requires < PHP 5.6 and another requires > PHP 7.1, that is no problem.

### Before we start

For these examples, we will use the base URL 'http://docker-laravel.test'. You will need to ensure that this URL resolves to your local machine. You can either install a DNS service locally such as [dnsmasq](http://www.thekelleys.org.uk/dnsmasq/doc.html), or you can edit your hosts file and add the following on a new line.

```
# /etc/hosts
127.0.0.1 docker-laravel.test
```

We also use port 80 for all examples. If you have apache or nginx running on your machine already you will get errors about not being able to bind port 80. In such cases swap references to port 80 to use port 8080 on the host machine, then navigate to 'http://docker-laravel.test:8080' where instructed to navigate to 'http://docker-laravel.test'.

#### Cleaning up

If you want to go back to a completely clean slate, the following commands will remove all containers, images, volumes, and networks that we create.

```console
docker rm -f $(docker ps -aq)
docker image prune
docker volume prune
docker network prune
```

--------------------

## Choosing our environment

### Architecture

- Laravel 5.6 running on PHP 7.2
- Nginx 1.15.0
- Mysql 5.7
- Redis 4

### Selecting our images

We can use the following images on Docker Hub to build our application:

- [php:7.2-fpm](https://hub.docker.com/_/php/)
- [nginx:1.15](https://hub.docker.com/_/nginx/)
- [mysql:5.7](https://hub.docker.com/_/mysql/)
- [redis:4](https://hub.docker.com/_/redis/)

Lets first of all just pull all those images down now. This isn't strictly necessary as Docker will pull them for you when it requires them, but this will save time later.

```
docker pull php:7.2-fpm
docker pull nginx:1.15
docker pull mysql:5.7
docker pull redis:4
```

Next, we will just run the nginx container with the `docker run ...` command just to make sure everything is working.

```
docker run --rm -it -p 8080:80 nginx:1.15
```

Now visit http://localhost:8080 in your browser and you should see the default nginx page, you will also see the nginx log in the terminal. You can do `ctrl-c` in the terminal window to halt the server.

Let's break that command down:

`docker run` - The Docker run command, simple enough.

`--rm` - Once the container has finished running (the nginx process stops), delete the container.

`-it` - Attach an interactive tty to the running container. This allows us to send keystrokes to the container (e.g. ctrl-c to halt the server).

`-p 8080:80` - Forward port 8080 on our machine, to port 80 (nginx default port) on the container. We could also use `-p 80:80` to forward port 80 on our machine.

`nginx:1.15` - Use the nginx image with tag 1.15 which we pulled previously.

-----------------

## Setting up our projects

### Project structure

The following directory structure works well for me, but it is up to you how you like to set this up.

Create a projects folder somewhere on your filesystem e.g. `$HOME/Projects/` and add three files at the root of that folder `docker-compose.yml`, `sites.conf` and `phpinfo.php`.

```console
mkdir $HOME/Projects
cd $HOME/Projects
touch docker-compose.yml
touch sites.conf
touch phpinfo.php

# Add some php to the php info file
echo "<?php phpinfo();" > phpinfo.php
```

The reason we have created a sample php file `phpinfo.conf` is that we haven't set up our Laravel project yet, that requires a few more steps and we want to make sure everything is working up to this point before we move on to that.

### Nginx Config

We are going to mount our nginx config into the nginx container, some people might wish to extend the nginx container and create a new image with the config in it. That might be more suitable for production, but for development, this will suffice.

Edit sites.conf:

```conf
# $HOME/Projects/sites.conf

server {
  listen 80 default_server;

  root /srv/static/docker-laravel/public;

  add_header X-Frame-Options "SAMEORIGIN";
  add_header X-XSS-Protection "1; mode=block";
  add_header X-Content-Type-Options "nosniff";

  index index.html index.htm index.php;

  charset utf-8;

  location / {
    try_files $uri $uri/ /index.php?$query_string;
  }

  location = /favicon.ico { access_log off; log_not_found off; }
  location = /robots.txt  { access_log off; log_not_found off; }

  error_page 404 /index.php;

  location ~ \.php$ {
    fastcgi_split_path_info ^(.+\.php)(/.+)$;

    fastcgi_pass docker-laravel:9000;
    fastcgi_index index.php;
    include fastcgi_params;

    fastcgi_param SCRIPT_FILENAME /app/public$fastcgi_script_name;
  }
}
```

### Docker compose

Edit the docker-compose.yml and add the following contents

```yml
# $HOME/Projects/docker-compose.yml

version: "3"
services:
  nginx:
    image: nginx:1.15
    restart: always
    volumes:
      # This mounts the site config into the containers config dir for nginx.
      - ./sites.conf:/etc/nginx/conf.d/sites.conf
    ports:
      # Change to 8080:80 if running a web server on port 80 already.
      - "80:80"

  docker-laravel:
    image: php:7.2-fpm
    working_dir: /app
    volumes:
      # This mounts our phpinfo file into the container at the content route
      # The directory '/app/public' comes from our sites.conf directive:
      # 'fastcgi_param SCRIPT_FILENAME'
      # If you want to change this folder, ensure you also edit sites.conf
      - ./phpinfo.php:/app/public/index.php
    depends_on:
      - db
      - redis

  db:
    image: mysql:5.7
    restart: always
    environment:
      - MYSQL_ALLOW_EMPTY_PASSWORD=true
      - MYSQL_DATABASE=docker_laravel_db
    volumes:
      - ./data/db:/var/lib/mysql
    ports:

      # This is optional and allows us to use
      # Database tools (e.g. HeidiSQL/Workbench) at 127.0.0.1:3306
      # Change to something like 33066:3306 if already running mysql locally
      - "3306:3306"

  redis:
    image: redis
    restart: always
```

### Running the services

In a terminal, run:

```console
docker-compose up -d
```

Now visit http://docker-laravel.test (Ensure it is in your hosts file, and if you bound the port in docker-compose.yml to 8080 you will need http://docker-laravel.test:8080). You should see the phpinfo file that we created. If so then the nginx container `nginx` is successfully communicating with the PHP-FPM container `docker-laravel`.

#### Debugging issues

*If you see the nginx page, or 'File not found', then something has gone wrong with your nginx configuration. If you change the nginx config file sites.conf you will need to run `docker-compose restart nginx`. Any changes you make to docker-compose.yml must be proceeded with `docker-compose up -d` again to apply them to the running containers.*

*You can open bash in the in the nginx container with `docker-compose exec nginx /bin/bash` for a poke around.*

---------------------

## Setting up our Laravel project

Create a directory in your project directory which will hold all your project repositories, then create a new laravel application in this directory.

```console
mkdir $HOME/Projects/repositories
cd $HOME/Projects/repositories
laravel new docker-laravel
```

*I would then typically version control $HOME/Projects/repositories/docker-laravel*

### Creating a custom image

The issue we currently have, is that the library php:7.2-fpm image is not suitable for running a Laravel project as it is. We need to extend this image to install the extra dependencies.

This is the point where the value of Docker should really click. We are going to create an image which is perfectly suited to our codebase. In fact the image will include our source code, and if we choose, the image will become a container on a live server, serving web pages in production!

Create a file in the laravel project : `Dockerfile`

```conf
# $HOME/Projects/repositories/docker-laravel/Dockerfile

FROM php:7.2-fpm

# Install some packages in to our container.
RUN apt-get -yqq update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        apt-utils \
        libzip-dev \
        libpng-dev \
        libfreetype6-dev \
        libjpeg-dev \
        libjpeg62-turbo-dev \
        libmcrypt-dev \
        libpng-dev \
        autoconf \
        g++ \
        make \
        openssl \
        libssl-dev \
        libcurl4-openssl-dev \
        pkg-config \
        libsasl2-dev \
        libpcre3-dev \
        && apt-get clean \
        && rm -rf /var/lib/apt/lists/* /tmp/* /var/tmp/* \
        ;

# Install some php extensions.
RUN pecl install mcrypt-1.0.1 \
    && docker-php-ext-configure gd \
      --with-freetype-dir=/usr/include/ \
      --with-jpeg-dir=/usr/include/ \
    && docker-php-ext-install \
    mysqli \
    pdo_mysql \
    gd \
    && docker-php-ext-enable mcrypt \
    ;

# Set the default directory of the container.
WORKDIR /app

# Copy all the files from the current directory into
# the containers working directory (/app).
COPY --chown=www-data:www-data . .
```

*We will see later how we can re-use a lot of this rather than putting all this (and maintaining it) in all of our code bases.*

### Back to docker-compose.yml

We now need to tell Docker compose to use our image instead of the base php:7.2-fpm version. Edit the docker-laravel service in docker-compose.yml

```yml
# $HOME/Projects/docker-compose.yml

# ...

  docker-laravel:
    build: ./repositories/docker-laravel
    depends_on:
      - db
      - redis

# ...
```

Note that we use 'build' instead of 'image'. We can build the image manually and use 'image' like we did before. Infact we will do this shortly, but we are doing incremental improvements here. We also don't use the `working_dir` directive as we have specified that in the custom Dockerfile.

### Re running the services

Run the up command again. This will apply the new configuration.

```
docker-compose up -d
```

It will probably take a while the first time whilst it builds the image, installs packages and compiles in the new PHP extentions. Once it has finished, navigate to http://docker-laravel.test - you should see the laravel landing page.

### Service static files

Laravel's landing page (as of 5.6) has no static resources, so we need to add something to deal with the next issue. (If you are running an existing app you will already have noticed that the static CSS and images aren't loading so you can skip this step.)

Append some style rule to `$HOME/Projects/repositories/docker-laravel/resources/assets/sass/app.scss`

e.g.

```css
# $HOME/Projects/repositories/docker-laravel/resources/assets/sass/app.scss

body {
    background-color: blue !important;
}
```

Quickly run yarn and npm run dev to pull in the nodejs modules and compile the CSS (if you don't have node installed, just create a static file in the public folder and pull it into the html).

```console
yarn
npm run dev
```

Pull the stylesheet into `$HOME/Projects/repositories/docker-laravel/resources/views/welcome.blade.php` somewhere in the `<head>`.

```html
<head>
  <!-- ... -->

  <link href="/css/app.css" rel="stylesheet" type="text/css">

  <!-- ... -->
</head>
```

We now need to rebuild the docker image to pull the latest changes into our image, (the css file and html changes). This is cumbersome and we will use a feature of docker to get around this in the next section.

```
docker-compose build docker-laravel
docker-compose up -d
```

Reload the page, and it won't have the stylesheet applied. Open your browsers dev tools, go to network, and it will tell you that the file could not be found (404).

What happened? Well, the problem is that nginx doesn't have access to our static files. We have put the files into the php-fpm container, but we need to also add them to the nginx container so that nginx can serve static files. We will mount the repositories directory into the nginx container at the directory /srv/static/. We earlier configured the nginx.conf to search for static files for this site in '/srv/static/docker-laravel/public';

```yml
# $HOME/Projects/docker-compose.yml

# ...

  nginx:
    image: nginx:1.15
    restart: always
    volumes:
      - ./sites.conf:/etc/nginx/conf.d/sites.conf
      # Ensure nginx has the static files available.
      - ./repositories:/srv/static/
    ports:
      # Change to 8080:80 if running a web server on port 80 already.
      - "80:80"

# ...
```

Run `docker-compose up -d` again and the static CSS files should now load.

### Live editing files

As touched on in the last section, this currently isn't great. We cannot rebuild the container every time we make a change. The solution involves editing the docker-compose.yml file again and using the volumes directive that we have already used a couple of times.

```yml
# $HOME/Projects/docker-compose.yml

# ...

  docker-laravel:
    build: ./repositories/docker-laravel
    # Add this mounted volume to basically sync our project files with
    # the container, for development.
    volumes:
      - ./repositories/docker-laravel:/app
    depends_on:
      - db
      - redis

# ...
```

Run `docker-compose up -d` again to apply this config, and then edit your files live.

If you get permission errors about writing to logs and cache, within a development environment, you can give the mounted files appropriate permissions for the user id for PHP-FPM process to write to.

### A quick note on Dockerfile COPY vs mounting volumes

You might ask, what is the point of COPY-ing the application files into the image within the Dockerfile if you are going to mount the project directory into the container? Well, if you only ever want a development environment, there is no problem with not copying any source code into the container. However, I wanted to demonstrate the real essence of Docker, whereby we have an image, with the source code, and everything needed to run the source code within a single image. You could easily take that image, and run it in a cloud, and with some environment variables set, it would work, guaranteed.

### Connecting up the database and redis containers

At this point, sI want to say that Docker networking is way beyond the scope of this post (it would double in length). I really recommend reading the [documentation](https://docs.docker.com/network/) at some point once comfortable with docker. It is worth pointing out though that if you want to connect other services to your current docker-compose project services, you will need to either expose a port to them, or use the docker-compose configuration docs to explicitly set up a network, that other external containers or processes can attach to.

The only thing left to do is to connect up the database services. Docker compose creates a Docker virtual network for us that allows inter-service communication by using the service name. So in this example, nginx can communicate with the phpfpm container running Laravel by using the hostname 'docker-laravel'. This is a very powerful feature that allows really simple service discovery.

So in our Laravel .env file, all we need to do is set the following values:

```console
DB_HOST=db # The name of the mysql service in docker-compose.yml

# Unprotected DB for development only.
DB_USERNAME=root
DB_PASSWORD=
DB_DATABASE=docker_laravel_db

REDIS_HOST=redis

CACHE_DRIVER=redis
SESSION_DRIVER=redis
QUEUE_DRIVE=redis
```

Now to migrate the database we can run. If the database doesn't exist, you will need to connect to it using a mysql client and connect through the forwarded port we configured in docker-compose.yml. 

```
docker-compose exec docker-laravel php artisan migrate
```

Now we should have a fully working Laravel development environment, using Docker!

## Conclusion

In this post, we went through building a development environment using Nginx and Php-fpm.