# 带 IK 中文分词的 Elasticsearch
#
# 为什么自己构建：官方镜像不含中文分词插件，取值召回会退化成 standard 分词
# （"镇海炼化" 被切成单字），召回质量明显下降。
# 插件版本必须与 ES 版本严格一致，升级 ES 时同步改这里。
FROM docker.elastic.co/elasticsearch/elasticsearch:8.15.0

RUN bin/elasticsearch-plugin install --batch \
    https://get.infini.cloud/elasticsearch/analysis-ik/8.15.0
