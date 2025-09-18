import { render, screen } from '@testing-library/react';
import App from './App';

// Mock fetch
global.fetch = jest.fn(() =>
  Promise.resolve({
    json: () => Promise.resolve([]),
  })
);

test('renders microservices app', () => {
  render(<App />);
  const linkElement = screen.getByText(/Microservices App/i);
  expect(linkElement).toBeInTheDocument();
});