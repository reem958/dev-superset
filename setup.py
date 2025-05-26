from setuptools import find_packages, setup
import os

version_string = "4.1.2"  # Manual versioning

setup(
    name="apache_superset",
    version=version_string,
    packages=find_packages(exclude=["superset-frontend"]),  
    include_package_data=False,  # No static files
    zip_safe=False,
    entry_points={
        "console_scripts": ["superset=superset.cli.main:superset"],
        "sqlalchemy.dialects": [
            "postgres.psycopg2 = sqlalchemy.dialects.postgresql:dialect",
            "postgres = sqlalchemy.dialects.postgresql:dialect",
        ],
    },
)