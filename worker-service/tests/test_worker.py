import pytest
from unittest.mock import patch, MagicMock
import sys
import os

# Add src to path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), '..', 'src'))

from worker import process_job, get_db_connection

def test_process_job():
    """Test that process_job completes successfully"""
    result = process_job(1)
    assert result is True

@patch('worker.psycopg2.connect')
def test_get_db_connection(mock_connect):
    """Test database connection"""
    mock_conn = MagicMock()
    mock_connect.return_value = mock_conn
    
    conn = get_db_connection()
    
    mock_connect.assert_called_once()
    assert conn == mock_conn