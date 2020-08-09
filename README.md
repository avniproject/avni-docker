## Set up avni environment using Docker Compose

Docker compose requires docker engine to be installed in your machine. So install docker engine from [here](https://docs.docker.com/engine/install/#server), 
then you need to install docker compose from [here](https://docs.docker.com/compose/install/).

For setting up avni server and webapp locally you don't need to clone the entire project. Simply copy `docker-compose.yml` file and run `docker-compose up`. This will 
start avni server and you can access webapp using `http://localhost:8021/`. All the db data is saved in the external volume, as long as you stop the containers 
gracefully using `docker-compose down`.


## Important commands
`docker pull vind3v/avni-server:3.7` to pull a docker image.

`docker run vind3v/avni-server:3.7` to run a image.

`docker exec -it avni-db bin/sh` to ssh into db container.

`docker-compose up` to bring up the env.

`docker-compose down` to bring down the env.

`docker-compose down -v` to bring down the env and delete volumes.

`docker-compose stop` to stop the containers.

`docker-compose start` to start the stopped containers.


All `docker-compose` commands should be run from the directory containing `docker-compose.yml` file
