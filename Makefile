up:
	docker-compose up -d

down:
	docker-compose down

send:
	bash scripts/sendmail.sh

logs:
	docker logs -f mail-postfix	

reproduce:
	bash scripts/reproduce.sh
