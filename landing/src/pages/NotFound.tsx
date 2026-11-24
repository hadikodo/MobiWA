import { Link } from 'react-router-dom';

export default function NotFound() {
  return (
    <section className="notfound container">
      <h1>404</h1>
      <p>This page doesn’t exist.</p>
      <Link className="btn btn-primary" to="/">
        Back to home
      </Link>
    </section>
  );
}
