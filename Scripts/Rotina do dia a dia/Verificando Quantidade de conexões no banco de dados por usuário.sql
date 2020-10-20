SELECT
    login_name,
    COUNT(*)
FROM
    sys.dm_exec_sessions
group by login_name
order by 1