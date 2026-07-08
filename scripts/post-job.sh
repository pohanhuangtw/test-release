echo job completed clean up
echo PWD = $PWD
sudo rm -rf *
docker system prune -a -f
sudo rm -rf /home/neuvector/.docker/manifests
