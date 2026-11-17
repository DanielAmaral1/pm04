# Etapa 1: Construção da aplicação
FROM node:18-alpine

# Definindo o diretório de trabalho dentro do container
WORKDIR /app

# Copiando o package.json e o package-lock.json para instalar as dependências
COPY package*.json ./

# Instalando as dependências do projeto
RUN npm install

# Copiando o restante do conteúdo do projeto para o container
COPY . .

# Expondo a porta que o backend vai usar (5000)
EXPOSE 5000

HEALTHCHECK --interval=10s --timeout=5s --retries=5 --start-period=15s \
  CMD node -e "require('http').get('http://localhost:5000/health', r => process.exit(r.statusCode===200?0:1)).on('error', () => process.exit(1))"

# Comando para rodar a aplicação
CMD ["node", "index.js"]
