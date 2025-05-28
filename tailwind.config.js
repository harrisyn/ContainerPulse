/** @type {import('tailwindcss').Config} */
module.exports = {
  content: [
    "./src/**/*.{html,js,ejs}",
    "./src/web/views/**/*.ejs",
    "./node_modules/flowbite/**/*.js"
  ],
  theme: {
    extend: {
      colors: {
        'portainer-blue': '#4285F4',
        'portainer-dark': '#1E2029',
        'portainer-light': '#F5F5F7',
        'portainer-success': '#28a745',
        'portainer-warning': '#ffc107',
        'portainer-danger': '#dc3545',
        'portainer-info': '#17a2b8'
      }
    },
  },
  plugins: [
    require('flowbite/plugin')
  ],
}
