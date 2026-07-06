{% macro generate_surrogate_key(fields) %}
    TO_HEX(MD5(CONCAT(
        {% for field in fields %}
            COALESCE(CAST({{ field }} AS STRING), 'NULL')
            {% if not loop.last %}, '|', {% endif %}
        {% endfor %}
    )))
{% endmacro %}
