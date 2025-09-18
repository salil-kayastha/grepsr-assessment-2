import React, { useState, useEffect } from 'react';

function App() {
  const [items, setItems] = useState([]);
  const [newItem, setNewItem] = useState('');
  const [loading, setLoading] = useState(false);

  const API_BASE = process.env.REACT_APP_API_URL || 'http://localhost:3001';

  useEffect(() => {
    fetchItems();
  }, []);

  const fetchItems = async () => {
    try {
      console.log('Fetching items from:', `${API_BASE}/api/items`);
      const response = await fetch(`${API_BASE}/api/items`);
      console.log('Fetch response status:', response.status);
      const data = await response.json();
      console.log('Fetched items:', data);
      setItems(data);
    } catch (error) {
      console.error('Error fetching items:', error);
    }
  };

  const addItem = async () => {
    if (!newItem.trim()) return;
    
    setLoading(true);
    try {
      console.log('Adding item:', newItem);
      console.log('API URL:', `${API_BASE}/api/items`);
      
      const response = await fetch(`${API_BASE}/api/items`, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ name: newItem }),
      });
      
      console.log('Add item response status:', response.status);
      
      if (response.ok) {
        const result = await response.json();
        console.log('Item added successfully:', result);
        setNewItem('');
        fetchItems();
      } else {
        const error = await response.json();
        console.error('Server error:', error);
      }
    } catch (error) {
      console.error('Error adding item:', error);
    } finally {
      setLoading(false);
    }
  };

  return (
    <div className="App">
      <header>
        <h1>Microservices App</h1>
      </header>
      <main>
        <div className="add-item">
          <input
            type="text"
            value={newItem}
            onChange={(e) => setNewItem(e.target.value)}
            onKeyPress={(e) => e.key === 'Enter' && addItem()}
            placeholder="Enter new item"
          />
          <button onClick={addItem} disabled={loading}>
            {loading ? 'Adding...' : 'Add Item'}
          </button>
        </div>
        <div className="items-list">
          <h2>Items</h2>
          <ul>
            {items.map((item) => (
              <li key={item.id}>
                {item.name} - {new Date(item.created_at).toLocaleString()}
              </li>
            ))}
          </ul>
        </div>
      </main>
    </div>
  );
}

export default App;