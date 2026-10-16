-- Fictional lab data, created only when PostgreSQL initializes an empty volume.
CREATE TABLE demo_items (
    id integer PRIMARY KEY,
    name text NOT NULL,
    quantity integer NOT NULL CHECK (quantity >= 0)
);

INSERT INTO demo_items (id, name, quantity) VALUES
    (1, 'Produit fictif A', 10),
    (2, 'Produit fictif B', 20),
    (3, 'Produit fictif C', 30);
