# This script is to build scanner with github action
#
echo -e "\n******************* Scanner $NV_BUILD_BRANCH Build Start *******************\n"
echo -e "*** VULN_VER=$VULN_VER ***"

SAVE_CWD=`pwd`

mkdir -p stage || { echo "Failed make build dir"; exit 1; }
cd ./stage || { echo "Failed cd into"; exit 1; }

echo -e "\n*** git clone scanner ***\n"
rm -rf scanner
rm -rf sigstore-interface
git clone https://github.com/neuvector/scanner.git || { echo "Failed git clone scanner"; exit 1; }
git clone https://github.com/neuvector/sigstore-interface.git || { echo "Failed git clone sigstore-interface"; exit 1; }

# Create database
echo -e "\n*** copy database ***\n"
wget https://neuvector-scanner.s3.us-west-2.amazonaws.com/$VULN_VER/cvedb.regular
mkdir -p scanner/data
mv cvedb.regular scanner/data/

# Create binary and database

echo -e "\n*** build sigstore-interface binary ***\n"
cd ./sigstore-interface

GITREV=`git rev-parse --short HEAD`
echo -e "*** GITREV=$GITREV ***\n"

echo -e "\n*** make binary ***\n"
make binary || { echo "Failed make binary"; exit 1; }

cd ..

echo -e "\n*** build scanner binary ***\n"
cd ./scanner || { echo "Failed cd into scanner"; exit 1; }

if [[ ! -z "$SCANNER_REV" ]]; then
   git checkout $SCANNER_REV
fi

GITREV=`git rev-parse --short HEAD`
echo -e "*** GITREV=$GITREV ***\n"

echo -e "\n*** make binary ***\n"
make binary || { echo "Failed make binary"; exit 1; }

cd .. || { echo "Failed cd into the parent"; exit 1; }

# Make image

echo -e "\n*** write version label ***\n"
cd ./scanner/build
sed -i -e 's/git.xxxx/'"$GITREV"'/g' ./Dockerfile.scanner
sed -i -e 's/vuln.xxxx/'"$VULN_VER"'/g' ./Dockerfile.scanner
cd ../../

echo -e "\n*** copy Makefile ***\n"
cp scanner/Makefile Makefile || { echo "Failed to copy Makefile"; exit 1; }
cp scanner/build/dockerignore .dockerignore

echo -e "\n*** build scanner container ***\n"
make scanner_image || { echo "Failed to make scanner image"; exit 1; }

cd $SAVE_CWD

# clean up
sudo rm -rf stage

echo -e "\n*** GITREV=$GITREV ***"
echo -e "*** vuln. database: $VULN_VER***"

echo -e "\n******************* Scanner Build Succeed *******************\n"

exit 0
