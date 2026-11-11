// ==========================================================================
// Frieren Startpage Core Application (Clock, Live Weather, Search)
// ==========================================================================

// 1. Clock & Date (24-Hour Format)
function updateClock() {
  const now = new Date();
  
  // Format Time: 24-hour digital with seconds (HH:MM:SS)
  const hours = String(now.getHours()).padStart(2, '0');
  const minutes = String(now.getMinutes()).padStart(2, '0');
  const seconds = String(now.getSeconds()).padStart(2, '0');

  const timeStr = `${hours}:${minutes}:${seconds}`;
  document.getElementById('clock-digits').textContent = timeStr;

  // Format Date: e.g. Friday, October 16
  const options = { weekday: 'long', month: 'long', day: 'numeric' };
  const dateStr = now.toLocaleDateString('en-US', options);
  document.getElementById('clock-date').textContent = dateStr;
}

// 2. Live Weather (Bauan, Batangas via Open-Meteo)
async function updateWeather() {
  try {
    const res = await fetch(
      'https://api.open-meteo.com/v1/forecast?latitude=13.79&longitude=121.01&current=temperature_2m,relative_humidity_2m,apparent_temperature,weather_code'
    );
    if (!res.ok) return;
    const data = await res.json();
    const curr = data.current;
    if (!curr) return;

    const temp = Math.round(curr.temperature_2m);
    const feelsLike = Math.round(curr.apparent_temperature);
    const humidity = Math.round(curr.relative_humidity_2m);
    const code = curr.weather_code;

    // Weather icon determination
    let icon = '☼';
    if (code >= 1 && code <= 3) icon = '🌤';
    else if (code >= 45 && code <= 48) icon = '🌫';
    else if (code >= 51 && code <= 67) icon = '🌧';
    else if (code >= 80 && code <= 82) icon = '🌦';
    else if (code >= 95) icon = '⛈';

    document.getElementById('weather-icon').textContent = icon;
    document.getElementById('weather-temp').textContent = `${temp}°`;
    document.getElementById('weather-feels').textContent = `${feelsLike}° Feels like`;
    document.getElementById('weather-humidity').textContent = `${humidity}% Humidity`;
  } catch (err) {
    console.log('Using offline weather preset');
  }
}

// 3. Search Bar Handler
function setupSearch() {
  const form = document.getElementById('search-form');
  const input = document.getElementById('search-input');

  form.addEventListener('submit', (e) => {
    e.preventDefault();
    const query = input.value.trim();
    if (query) {
      // Check if it's a URL
      if (/^(https?:\/\/|[a-z0-9]+\.[a-z]{2,})/i.test(query)) {
        const url = query.startsWith('http') ? query : `https://${query}`;
        window.location.href = url;
      } else {
        window.location.href = `https://www.google.com/search?q=${encodeURIComponent(query)}`;
      }
    }
  });
}

// Initialize on load
document.addEventListener('DOMContentLoaded', () => {
  updateClock();
  setInterval(updateClock, 1000);
  updateWeather();
  setInterval(updateWeather, 15 * 60 * 1000); // Check weather every 15 min
  setupSearch();
});
