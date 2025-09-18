import os
import time
import logging
import psycopg2
from datetime import datetime

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger('worker-service')

# Database connection
def get_db_connection():
    return psycopg2.connect(
        host=os.getenv('DB_HOST', 'db'),
        database=os.getenv('DB_NAME', 'appdb'),
        user=os.getenv('DB_USER', 'postgres'),
        password=os.getenv('DB_PASSWORD', 'password'),
        port=os.getenv('DB_PORT', '5432')
    )

# Process job
def process_job(job_id):
    logger.info(f"Processing job {job_id}")
    # Simulate some work
    time.sleep(2)
    logger.info(f"Completed job {job_id}")
    return True

def main():
    logger.info("Worker service started")
    
    # Initialize database
    try:
        conn = get_db_connection()
        cur = conn.cursor()
        cur.execute('''
            CREATE TABLE IF NOT EXISTS jobs (
                id SERIAL PRIMARY KEY,
                status VARCHAR(20) DEFAULT 'pending',
                created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
                processed_at TIMESTAMP
            )
        ''')
        conn.commit()
        cur.close()
        conn.close()
        logger.info("Database initialized")
    except Exception as e:
        logger.error(f"Database initialization error: {e}")
    
    # Main processing loop
    job_id = 1
    while True:
        try:
            conn = get_db_connection()
            cur = conn.cursor()
            
            # Create a new job
            cur.execute(
                'INSERT INTO jobs (status) VALUES (%s) RETURNING id',
                ('pending',)
            )
            job_id = cur.fetchone()[0]
            conn.commit()
            
            # Process the job
            success = process_job(job_id)
            
            # Update job status
            cur.execute(
                'UPDATE jobs SET status = %s, processed_at = %s WHERE id = %s',
                ('completed' if success else 'failed', datetime.now(), job_id)
            )
            conn.commit()
            
            cur.close()
            conn.close()
            
        except Exception as e:
            logger.error(f"Error processing job: {e}")
            time.sleep(5)  # Wait before retrying
        
        time.sleep(10)  # Wait before next job

if __name__ == '__main__':
    main()