FROM mcr.microsoft.com/dotnet/sdk:6.0

WORKDIR /app

ENV LD_LIBRARY_PATH /app

COPY . .

COPY ./appsettings.json ./appsettings.LocalTestNode.json /app/
COPY ./W1ptWN5n5mfdVvh3khTRm9KMJCAUdge9txNyVtyvZaYRYcqc1.json /root/.local/share/aelf/keys/
ENV ASPNETCORE_ENVIRONMENT=LocalTestNode

ENTRYPOINT ["dotnet", "/app/AElf.Launcher.dll"]
