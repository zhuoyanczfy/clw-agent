"""config 项目包初始化。

生产环境使用 MySQL（PyMySQL 驱动）：Django 的 mysql 后端默认找
MySQLdb（mysqlclient），需要 install_as_MySQLdb() 注册 PyMySQL 才能工作。
本地开发无 PyMySQL 时静默跳过，不影响 SQLite。
"""
try:
    import pymysql
    pymysql.install_as_MySQLdb()
except ImportError:
    pass
