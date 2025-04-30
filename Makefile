up:
	docker-compose up -d

down:
	docker-compose down

send:
	bash scripts/sendmail.sh

logs:
	tail -f artifacts/latest/postfix.log

reproduce:
	bash scripts/reproduce.sh
