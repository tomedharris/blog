---
title: "Docker and Laravel development environment 2018 Part 2"
# date: 2018-06-18
tags: ["php", "docker", "laravel", "devops"]
draft: true
---

## Introduction

This post will expand upon a blog post I made about using Docker with Laravel. We will focus more on how to support multiple Laravel projects using a single Laravel-Development Docker image.

To get started you should have cloned the following git repository GIT REPO.

### Building a reusable Laravel container

In the last example we created a Dockerfile within the application directory, this would have been placed under version control. Now this is absolutely fine, but if you are working on several Laravel projects at the same time, or perhaps you are using Lumen to build microservices, it isnt reasonable to have the same Dockerfile inside each project. Lets say that a future version of Laravel is released that has a dependency on some new PHP extension, we would now need to go through each project, copy pasting the lines into the Dockerfile to install that extension. Much better would be to build a new image which extends the `php:7.2-fpm` docker image, and use that for our development needs. Of course nothing is stopping you from tweaking that new custom image with a Dockerfile in each project if one of your projects needs, for example, MongoDB, where all of your other projects don't.

### Create a place for our images

Create a directory in your Projects folder

```
mkdir -p $HOME/Projects/DockerImages/Laravel
cd $HOME/Projects/DockerImages/Laravel

touch Dockerfile
```

In Dockerfile put the following contents

```conf
# $HOME/Projects/DockerImages/Laravel/Dockerfile

FROM php:7.2-fpm

# Install some packages into our container.
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

# Set the default directory of the container.
WORKDIR /app
```

You may notice that we have loeft out `COPY`ing any files into the image. We could have put a fresh Laravel projects files into the container if we wished but that is outside of the scope of this post. If you want to add you individual projects files into the image as in the last post, create a Dockerfile in the root of your project, extending from this one that we are about to build, then use the `COPY` directive.

Now we need to build and tag our image:

```console
docker build -t yourname/laravel:5.6 .
```

Notice how we build the image and tag it with the Laravel version! This means that we can have a different image for running multiple projects, on different Laravel versions.

Once that has run we can now edit the services in docker-compose.yml to use the image instead of building the image in the repository.

We could leave it as `build: ./DockerImages/Laravel/` instead of using `image:` and that is perfectly reasonable, but if you want to share this environment with other developers, it is best to use a tagged built image, which you can push to a Docker registry. I won't go into how that can be done, but if you build the image and push it to a registry, other developers can just use pull the image without having to build it. Infact if you supply them with the docker-file, they can use the environment to without any knowledge of Docker, just using the `docker-compose up -d` command to start everything.

Anyway, edit the file:

```yml
# $HOME/Projects/docker-compose.yml

# ...

  docker-laravel:
    image: yourname/laravel:5.6
    volumes:
      - ./repositories/docker-laravel:/app
    depends_on:
      - db
      - redis

# ...
```

Now do `docker-compose up -d` and you should see that everything should work as before.

### Make nginx pass to the correct php-fpm container using convention

We could quite easily use the current setup to run multiple Laravel projects now by creating mutliple nginx configurations, however it would require recreating the nginx container everytime we wish to add a new Project, and also maintaining multiple nginx configs.

What we can do, is pass the fastcgi request to the correct container based on its domain name, and matching that up with the service name within docker-compose.yml

Edit the nginx config file to look like:

```conf
# $HOME/Projects/sites.conf

server {
  listen 80 default_server;

  # Store the url less the tld in a variable $projectname
  server_name ~^(?<projectname>[\w-]+)\.test;
  
  # Use the variable to fetch static files from the directory /srv/static/[PROJECT_NAME]
  root /srv/static/$projectname/public;

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

    # Pass the request to php-fpm running on url $projectname
    # Remember that docker-compose will create a network, and this nginx container will
    # be able to contact another container via its docker-compose name.
    fastcgi_pass $projectname:9000;
    fastcgi_index index.php;
    include fastcgi_params;

    fastcgi_param SCRIPT_FILENAME /app/public$fastcgi_script_name;
    fastcgi_param SERVER_NAME     $projectname.test;
  }
}
```

The comments within the file should show what we are doing here, but basically we extract a project name from the url (everything before '.test'). We then leverage the wonderful feature of DockerCompose that services are resolvable by their service name, and use the project name for the fastcgi_pass directive.

We also use the project name for looking up static files so it is important that the project within the mounted repositories volume is named the same as the service within docker-compose.yml

Now we need to re-start the nginx service to recreate the container with the new config.

```console
docker-compose up -d --force-recreate nginx
```

## Development only images

Sometimes you want to install dev tools within the image but only for development. My recommendation would be to create a Production ready docker image, and extend this to include dev specific tools for the dev environment. An example might be installing XDebug (more below) where you will certainly want this in development, but not in production.

As of now xdebug is a pain to get working correctly with this setup due to option `xdebug.remote_connect_back` not working correctly, but it is such an importent tool that the cleanest way I can get around this is by adding your IP address on the local network to an evironment variable within docker-compose.yml and making use of that with xdebug's configuration setting for `remote_host`.

Create a new folder in DockerImages

```console
mkdir -p $HOME/Projects/DockerImages/Laravel
cd $HOME/Projects/DockerImages/Laravel

touch Dockerfile
touch xdbug.ini
```

Add to the Dockerfile the following contents:

```conf
# $HOME/Projects/DockerImages/Laravel-Dev/docker-compose.yml

FROM yourname/laravel:5.6

RUN pecl install xdebug-2.6.0 \
    && docker-php-ext-enable xdebug \
    ;

COPY xdebug.ini /usr/local/etc/php/conf.d/
```

```conf
xdebug.remote_enable=1
xdebug.remote_host=${XDEBUG_REMOTE_HOST}
xdebug.remote_handler=dbgp
xdebug.remote_port=9000
xdebug.idekey=phpstorm
xdebug.remote_autoconnect=1
```

Now build and tag this image

```console
docker build -t yourname/laravel:5.6-dev
```

Now edit docker-compose.yml and add that environemt variable:

```yml
# $HOME/Projects/docker-compose.yml

# ...

  docker-laravel:
    image: yourname/laravel:5.6
    volumes:
      - ./repositories/docker-laravel:/app
    depends_on:
      - db
      - redis
    environment:
      - "XDEBUG_REMOTE_HOST=192.168.1.123" # Your local network IP.

# ...
```

(it is worth noting that you can set any evironment variable here and override anything in laravels .env file which is very useful for deploying to production)

Now you can use this image within docker-compose.yml for your development and have access to xdebug!

## Conclusion

This post has extended upon an older post by providing a way to build a reuable docker image, as well as how to connect nginx to multple php-fpm containers running within a network.
