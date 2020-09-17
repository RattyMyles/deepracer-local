#!/usr/bin/env bash

#Changing Track does not work ...!
#echo "List of supported worlds
#(Taken from /opt/install/deepracer_simulation_environment/share/deepracer_simulation_environment/models)
#
#AWS_track                   bot_car
#Albert                      box_obstacle
#AmericasGeneratedInclStart  camera
#Bowtie_track                reInvent 2019_track
#Canada_Training             reInvent2019_wide
#China_track                 reInvent2019_wide_mirrored
#FS_June2020                 reinvent_base
#July_2020                   reinvent_carpet
#LGSWide                     reinvent_carpet_carpet
#Mexico_track                reinvent_concrete
#New_York_Track              reinvent_concrete_concrete
#Oval_track                  reinvent_grass_asphalt
#Spain_track                 reinvent_lines_walls
#Straight_track              reinvent_wood
#Tokyo_Training_track        reinvent_wood_wood
#Vegas_track                 top_camera
#Virtual_May19_Train_track
#
#"

WORLD_NAME=reinvent_base
#WORLD_NAME=AWS_track

sed -i "s/^\(WORLD_NAME\s*=\s*\).*$/WORLD_NAME=$WORLD_NAME/" config.env
sed -i "s/^\(WORLD_NAME:\s* \s*\).*$/WORLD_NAME: \"$WORLD_NAME\"/" data/minio/bucket/custom_files/training_params.yaml

if hash nvidia-docker 2>/dev/null; then
    echo "GPU Enabled"
    sed -i 's/^\(GPU_AVAILABLE\s*=\s*\).*$/GPU_AVAILABLE=True/' config.env
    sed -i 's/^\(ENABLE_GPU_TRAINING\s*=\s*\).*$/ENABLE_GPU_TRAINING=True/' config.env
    sed -i 's/^\(ENABLE_GPU_TRAINING:\s* \s*\).*$/ENABLE_GPU_TRAINING: "True"/' data/minio/bucket/custom_files/training_params.yaml
    #sed -i 's/\(image: awsdeepracercommunity\/deepracer-robomaker\s*:\s*\).*$/image: awsdeepracercommunity\/deepracer-robomaker:gpu/' docker-compose.yml
else
    echo "nvidia-docker is not installed"
    echo "GPU Disabled"
    sed -i 's/^\(GPU_AVAILABLE\s*=\s*\).*$/GPU_AVAILABLE=False/' config.env
    sed -i 's/^\(ENABLE_GPU_TRAINING\s*=\s*\).*$/ENABLE_GPU_TRAINING=False/' config.env
    sed -i 's/^\(ENABLE_GPU_TRAINING:\s* \s*\).*$/ENABLE_GPU_TRAINING: "False"/' data/minio/bucket/custom_files/training_params.yaml
    #sed -i 's/\(image: awsdeepracercommunity\/deepracer-robomaker\s*:\s*\).*$/image: awsdeepracercommunity\/deepracer-robomaker:cpu-avx2/' docker-compose.yml   
fi

source config.env

if [ -e data/minio/bucket/current/model/deepracer_checkpoints.json ] ; then
  echo "WARNING: Files were found in the current model directory data/minio/bucket/current/"
  echo "Please run ./delete_last_run.sh or relocate the current model dir before starting a new training session."
  echo "You cannot currently restart training of an existing model, instead you should move the current model dir to rl-deepracer-pretrained and enable pretrained in hyperparams.json"
  exit 1
fi

if [ ! -e data/minio/bucket/current/training_params.yaml ]; then
    mkdir -p data/minio/bucket/current
    cp data/minio/bucket/custom_files/training_params.yaml data/minio/bucket/current
fi

export ROBOMAKER_COMMAND="./run.sh run distributed_training.launch"
export CURRENT_UID=$(id -u):$(id -g)

docker-compose -f ./docker-compose.yml up -d

if [ "$ENABLE_LOCAL_DESKTOP" = true ] ; then
    echo "Starting desktop mode... waiting 30s for Sagemaker container to start"
    sleep 30

    echo 'Attempting to pull up sagemaker logs...'
    SAGEMAKER_ID="$(docker ps | awk ' /sagemaker/ { print $1 }')"

    echo 'Attempting to open stream viewer and logs...'

	if [ -f "/etc/arch-release" ]; then
		#We are Manjaro!
		exo-open --launch WebBrowser http://localhost:8888/stream_viewer?topic=/racecar/deepracer/kvs_stream
		exo-open --launch TerminalEmulator  sh -c "docker logs -f $SAGEMAKER_ID"
		exo-open --launch TerminalEmulator  sh -c 'docker logs -f robomaker'
		vncviewer localhost:8080 &
	else
		gnome-terminal --tab -- sh -c "echo viewer;x-www-browser -new-window http://localhost:8888/stream_viewer?topic=/racecar/deepracer/kvs_stream;sleep 1;wmctrl -r kvs_stream -b remove,maximized_vert,maximized_horz;sleep 1;wmctrl -r kvs_stream -e 1,100,100,720,640"
		gnome-terminal --tab -- sh -c "docker logs -f $SAGEMAKER_ID"
		gnome-terminal --tab -- sh -c 'docker logs -f robomaker'
		vncviewer localhost:8080 &
	fi
else
    echo "Started in headless server mode. Set ENABLE_LOCAL_DESKTOP to true in config.env for desktop mode."
    if [ "$ENABLE_TMUX" = true ] ; then
        ./tmux-logs.sh
    fi
fi
