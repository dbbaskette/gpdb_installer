## Greenplum Cluster Restart After pg_hba.conf Changes

- The installer no longer restarts the cluster automatically after modifying `pg_hba.conf`.
- Rationale: In Greenplum (and PostgreSQL), a full restart is not required for `pg_hba.conf` changes—a configuration reload (`gpstop -u` or `SELECT pg_reload_conf();`) is sufficient.
- If you encounter connection issues after modifying `pg_hba.conf`, perform a manual restart:
  ```bash
  sudo -u gpadmin gpstop -a && sudo -u gpadmin gpstart -a
  ```
- This change avoids unnecessary restarts and potential errors during installation. 