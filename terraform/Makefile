.PHONY: check-deps init apply kill

PLAN_FILE="out.tfplan"

default: yolo

check-deps:
	@command -v psql > /dev/null || echo "Oops... 'psql' is not installed. Please install that first 'cause we gotta run some queries."; exit

init: check-deps
	@echo "✨ Setting up terraform... 🛠"
	@terraform fmt -recursive .
	@terraform init

plan: init
	@echo "✨ Starting terraform magic... 🧙"
	@terraform plan -out="${PLAN_FILE}"

apply:
	@echo "✨ Applying changes... 🚀"
	@terraform apply ${PLAN_FILE}

yolo: plan
	@echo "🔥 Let's goooooo... 🤪"
	@terraform apply -auto-approve ${PLAN_FILE}

kill:
	@echo "🔪 Killing 'em with fire!!! 🔥🔥🔥"
	@terraform destroy