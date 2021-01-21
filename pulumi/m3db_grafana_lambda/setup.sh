python3 -m venv venv
source venv/bin/activate
python -m pip install --upgrade pip setuptools wheel
python -m pip install -r requirements.txt
deactivate

pip install requests --target lambda_layer/python

pulumi config set aiven_cloud_region google-us-central1

pulumi config set aws:region us-west-2
