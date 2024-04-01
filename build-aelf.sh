#!/bin/bash
export PATH=$PATH:/opt/dotnet

DEBUG_FLAG=0

HOME_DIR=$(cd $(dirname "$0") && pwd )

function log() {
  if [[ $# -eq 1 ]];then
    msg=$1
    echo -e "$(date +"%Y-%m-%d %H:%M:%S") \033[32m[INFO]\033[0m ${msg}"
  elif [[ $# -eq 2 ]];then
    param=$1
    msg=$2
    if [[ ${param} = "-w" ]];then
      echo -e "$(date +"%Y-%m-%d %H:%M:%S") \033[34m[WARNING]\033[0m ${msg}"
    elif [[ ${param} = "-e" ]];then
      echo -e "$(date +"%Y-%m-%d %H:%M:%S") \033[31m[ERROR]\033[0m ${msg}"
      exit 1
    elif [[ ${param} = "-d" ]];then
      echo "$(date +"%Y-%m-%d %H:%M:%S") [DEBUG] ${msg}"
      if [[ ${DEBUG_FLAG} = 1 ]];then
        set -x
      fi
    fi
  fi
}

function git_url() {
  GITHUB_URL="${1:-https://github.com/AElfProject/AElf.git}"
  log "GitHub URL: ${GITHUB_URL}"
}

DOCKER_NUM=$(dpkg -l |grep  "^ii"|awk '{print $2}'|grep -c docker)
#if [ "${DOCKER_NUM}" -eq 0 ]; then
#  log -e "主机未安装 Docker 服务。"
#fi

function git_clone() {
  [ -z "${_BRANCH}" ] && { show_help; log -e "参数 -b | --branch 不能为空。"; }

  git_url "${_GIT_URL}"

  [ -d "${HOME_DIR}/AElf" ] && { rm -rf "${HOME_DIR}/AElf"; log "删除目录：${HOME_DIR}/AElf ."; }

  if ! git clone --recursive "${GITHUB_URL}" --branch "${_BRANCH}" --single-branch "${HOME_DIR}"/AElf; then
    log -e "克隆 GitHub 仓库 ${GITHUB_URL} 失败"
  fi
}

function dotnet_build() {
  [ -z "${_VERSION_NUM}" ] && { show_help; log -e "参数 -v | --version 不能为空。"; }

  [ -d "${HOME_DIR}/AElf/build" ] && { log "删除 build 目录：${HOME_DIR}/AElf/build"; rm -rf "${HOME_DIR}/AElf/build"; }

  log "执行脚本：${HOME_DIR}/AElf/scripts/download_binary.sh"
  bash "${HOME_DIR}"/AElf/scripts/download_binary.sh

  log "开始执行命令：dotnet publish"
  if [ "${_LOG_LEVEL}" = "Debug" ]; then
    dotnet publish "${HOME_DIR}"/AElf/AElf.All.sln \
      /p:NoBuild=false --version-suffix "${_VERSION_NUM}" \
      -o "${HOME_DIR}"/AElf/build /p:Platform="Any CPU"

    [ $? -ne 0 ] && log -e "执行 dotnet publish 命令失败。"

  else
    dotnet publish "${HOME_DIR}"/AElf/AElf.All.sln \
      /p:NoBuild=false --version-suffix "${_VERSION_NUM}" \
      --configuration Release -o "${HOME_DIR}"/AElf/build /p:Platform="Any CPU"

    [ $? -ne 0 ] && log -e "执行 dotnet publish 命令失败。"
  fi

  [ -f "${HOME_DIR}/AElf/build/AElf.Launcher.dll" ] || log -e "编译后不存在 AElf.Launcher.dll 文件, dotnet publish 失败。"
  log "编译成功。"
}

function is_exist_file() {
  _CONTRACTS_DIRECTORY=$1

  [ -z "${_IMAGES_NAME}" ] && { show_help; log -e "参数 -i | --images 不能为空。"; }

  if [ -n "${_CONTRACTS_DIRECTORY}" ]; then
    log "合约文件目录：${_CONTRACTS_DIRECTORY}"
    [ -d "${_CONTRACTS_DIRECTORY}" ] || log -e "不存在合约文件目录：${_CONTRACTS_DIRECTORY}"
    if ! cp -a "${_CONTRACTS_DIRECTORY}"/*.dll "${HOME_DIR}/AElf/build"; then
      log -e "替换创世合约文件 ${_CONTRACTS_DIRECTORY}/*.dll 失败。"
    fi
  fi

  [ -f "${HOME_DIR}/log4net.config" ] || log -e "不存在日志配置文件：log4net.config"
  if ! cp -a "${HOME_DIR}/log4net.config" "${HOME_DIR}/AElf/build"; then
    log -e "替换日志配置文件：${HOME_DIR}/log4net.config 失败。"
  fi
}

function docker_build() {
  [ -z "${_IMAGES_NAME}" ] && { show_help; log -e "参数 -i | --images 不能为空。"; }

  if [ -z "${_CONTRACTS_DIRECTORY}" ]; then
    is_exist_file
  else
    is_exist_file "${_CONTRACTS_DIRECTORY}"
  fi

  if ! docker buildx build --platform linux/amd64 -t "${_IMAGES_NAME}" -f "${HOME_DIR}"/Dockerfile "${HOME_DIR}"/AElf/build $@; then
    log -e "执行命令 docker build 失败。"
  fi
  
  log "成功构建 AELF Docker 镜像。"
}

function ssdb_is_running() {
  NAME=$1
  ssdb_num=$(ps -ef|grep ssdb-server | grep -c "${NAME}")
  [ "${ssdb_num}" -gt 0 ] || return 1
  return 0
}

function stop_ssdb() {
  ssdb_is_running ssdb8881 && { log "停止服务：ssdb8881";  /opt/ssdb8881/ssdb.sh stop; }
  ssdb_is_running ssdb8882 && { log "停止服务：ssdb8882";  /opt/ssdb8882/ssdb.sh stop; }
}

function clean_ssdb_data() {
  ssdb_is_running ssdb8881 || { log "删除 ssdb8881 数据。"; rm -rf /opt/ssdb8881/var/*; }
  ssdb_is_running ssdb8882 || { log "删除 ssdb8882 数据。"; rm -rf /opt/ssdb8882/var/*; }
}

function start_ssdb() {
  ssdb_is_running ssdb8881 || { log "启动服务：ssdb8881"; /opt/ssdb8881/ssdb.sh start; }
  ssdb_is_running ssdb8882 || { log "启动服务：ssdb8882"; /opt/ssdb8882/ssdb.sh start; }
}

function init_ssdb() {
  stop_ssdb
  clean_ssdb_data
  start_ssdb
}

function clean_docker_rabbitmq() {
  if [ -n "$(docker ps -aq --filter name=test-rabbitmq)" ]; then
    log "停止并删除 test-rabbitmq Docker 服务。"
    docker rm -f test-rabbitmq
  fi
}

function init_rabbitmq() {
  clean_docker_rabbitmq
  docker pull rabbitmq:management
  docker run -d -p 15672:15672 -p 5672:5672 \
    --hostname=rabbitmq-01 -e RABBITMQ_DEFAULT_USER=root \
    -e RABBITMQ_DEFAULT_PASS=123456 --privileged=true \
    --name test-rabbitmq rabbitmq:management
}

function clean_docker_redis() {
  if [ -n "$(docker ps -aq --filter name=test-redis)" ]; then
    log "停止并删除 test-redis docker 服务。"
    docker rm -f test-redis
  fi
}

function init_redis() {
  clean_docker_redis
  docker pull redis:latest
  docker run -d --name test-redis -p 6379:6379 redis:latest
}

function clean_docker_aelf_node() {
  if [ -n "$(docker ps -aq --filter name=aelf-node)" ]; then
    log "停止并删除 aelf-node docker 服务。"
    docker rm -f aelf-node
  fi

  log "清理 aelf 节点配置和日志。"
  [ -d "/opt/aelf-node/Logs" ] && rm -rf /opt/aelf-node/Logs
  [ -f "/opt/aelf-node/appsettings.json" ] && rm /opt/aelf-node/appsettings.json
}

function start_docker_aelf_node() {
  _NETWORK=$1
  _IMAGES_NAME=$2
  if ! cp -a "/opt/aelf-node/appsettings.json.${_NETWORK}" "/opt/aelf-node/appsettings.json"; then
    log -e "复制 aelf 节点配置文件：/opt/aelf-node/appsettings.json.${_NETWORK} 失败。"
  fi

  docker run -d --name aelf-node \
  -p 6801:6801 -p 8000:8000 -p 5001:5001 -p 5011:5011 \
  -v /opt/aelf-node:/opt/aelf-node \
  -v /opt/aelf-node/keys:/root/.local/share/aelf/keys \
  -w /opt/aelf-node --ulimit core=-1 --security-opt \
  seccomp=unconfined --privileged=true "${_IMAGES_NAME}" \
  dotnet /app/AElf.Launcher.dll
}

function hash() {
  HASH=$(curl -s -X 'GET' 'http://127.0.0.1:8000/api/blockChain/chainStatus' \
      -H 'accept: text/plain; v=1.0' | grep -v "Total" | jq ".GenesisBlockHash")
  [ "${HASH}" ] && return 1
  return 0
}

function GenesisBlockHash() {
  MainNet_GenesisBlockHash="73b6d1064013c0b34e6b4783d04a7c550863c95bd78e9b372fe8372577e290e8"
  TestNet_GenesisBlockHash="ca35103cb8edad6e4f804535c5106b79b9fa5257f764b19f042e0ffe78c035f8"

  if [ "$(docker inspect --format '{{.State.Running}}' aelf-node)" = "true" ]; then
    log "MainNet_GenesisBlockHash: ${MainNet_GenesisBlockHash}"
    log "TestNet_GenesisBlockHash: ${TestNet_GenesisBlockHash}"

    count=0
    MAX_WAIT=30
    until ! hash || [ $count -gt $MAX_WAIT ]
    do
      echo -n "." && sleep 1
      count=$(expr $count + 1)
    done

    log "HASH: ${HASH}"
  else
    log -e "AElf service is not started."
  fi
}


function check_network() {
  _NETWORK=$1
  if [ "${_NETWORK}" = "MainNet" ]; then
    return
  elif [ "${_NETWORK}" = "TestNet"  ]; then
    return
  elif [ "${_NETWORK}" = "LocalNet" ]; then
    return
  elif [ "${_NETWORK}" = "TestNet.Indexer" ]; then
    return
  elif [ "${_NETWORK}" = "MainNet.Indexer" ]; then
    return
  else
    log -e "-n | --network 参数错误，例：[MainNet|TestNet|LocalNet|TestNet.Indexer|MainNet.Indexer]。"
  fi
}

function build_all() {
  echo 
}


function clean() {
  stop_ssdb
  clean_ssdb_data
  clean_docker_rabbitmq
  clean_docker_redis
  clean_docker_aelf_node
}

function test() {

  [ -z "${_NETWORK}" ] && { show_help; log -e "参数 -n | --network 不能为空。"; }
  check_network "${_NETWORK}"

  [ -z "${_IMAGES_NAME}" ] && { show_help; log -e "参数 -i | --images 不能为空。"; }

  init_ssdb
  init_rabbitmq
  if [ "${_NETWORK}" = "TestNet.Indexer" ] || [ "${_NETWORK}" = "MainNet.Indexer" ]; then
    init_redis
  fi
  start_docker_aelf_node "${_NETWORK}" "${_IMAGES_NAME}"
  GenesisBlockHash
  sleep 10
  clean
}

function ex() {
  echo -e "\n使用详情请参考文档：https://hoopox.feishu.cn/wiki/wikcnsTbnyT68Wn50j46hNkU0N7 \n"
}

function show_help() {
  echo "Usage: $0 <command> ... [parameters ...]
Commands:
  clone                    克隆 GitHub 版本库代码文件。
  dotnet-build             对 GitHub 版本库代码进行编译。
  docker-build             构建 AELF Docker 镜像文件。
  test                     测试 AELF 镜像，对比创世块 GenesisBlockHash 值是否一致。
  clean                    清理 AELF，SSDB，RabbitMQ 服务和数据。
  ex                       命令示例。

Parameters:
  -h, --help                            显示此帮助消息。
  -n, --network <network>               设置 AELF 网络环境，例：MainNet/TestNet
  -b, --branch <branch>                 设置 AELF GitHub 版本库分支名称。
  -i, --images <image_name>             设置 AELF Docker 镜像名称。
  -v, --version <version>               设置 AELF 版本号。
  -l, --log-level <Debug>               设置 AELF 构建时 --configuration Debug 参数，默认：Release
  -C, --contracts-directory <dir>       合约文件目录，默认不替换合约文件。
  --git-url <url>                       git 仓库地址，默认：https://github.com/AElfProject/AElf.git
"
}

function _process() {
  _CMD=""
  while [ ${#} -gt 0 ]; do
    case "${1}" in
      -h | --help)
        show_help
        return
        ;;
      clone)
        _CMD="clone"
        ;;
      dotnet-build)
        _CMD="dotnet-build"
        ;;
      docker-build)
        _CMD="docker-build"
        ;;
      test)
        _CMD="test"
        ;;
      clean)
        _CMD="clean"
        ;;
      ex)
        _CMD="ex"
        ;;
      -n | --network)
        _NETWORK="$2"
        shift
        ;;
      -b | --branch)
        _BRANCH="$2"
        shift
        ;;
      -i | --images)
        _IMAGES_NAME="$2"
        shift
        ;;
      -v | --version)
        _VERSION_NUM="$2"
        shift
        ;;
      -l | --log-level)
        _LOG_LEVEL="$2"
        shift
        ;;
      -C | --contracts-directory)
        _CONTRACTS_DIRECTORY="$2"
        shift
        ;;
      --git-url)
        _GIT_URL="$2"
        shift
        ;;
      *)
        echo "未知参数：$1"
        show_help
        return
        ;;
    esac
    shift 1
  done

  case "${_CMD}" in
    clone)
      git_clone
      ;;
    dotnet-build)
      dotnet_build
      ;;
    docker-build)
      docker_build
      ;;
    test)
      test
      ;;
    clean)
      clean
      ;;
    ex)
      ex
      ;;
    *)
      echo "无效命令：${_CMD}"
      show_help
      return 1
      ;;
  esac
}

function main() {
  [ -z "$1" ] && show_help && return
  _process "$@"
}

main "$@"

