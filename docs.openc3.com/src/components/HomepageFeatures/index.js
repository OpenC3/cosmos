import React from 'react';
import clsx from 'clsx';
import styles from './styles.module.css';

const FeatureList = [
  {
    title: 'Easy to Configure',
    description: (
      <>
        OpenC3 COSMOS was designed from the ground up to be easy to configure. Simply define the messages needed to
        talk to your hardware (commands and telemetry), and you are ready to go!
      </>
    ),
  },
  {
    title: 'Modern Architecture',
    description: (
      <>
        Built with a modern design, cloud native, and ready to scale. OpenC3 COSMOS has a microservice architecture
        built to scale, and with fully maintained and up-to-date dependencies.
      </>
    ),
  },
  {
    title: 'Pick Your Favorite Language',
    description: (
      <>
        OpenC3 COSMOS supports both Ruby and Python for scripting and connecting to targets. Frontend applications can be written
        in Vue, React, Angular, or Svelte.  Whatever languages your team knows, we support.
      </>
    ),
  },
];

function Feature({title, description}) {
  return (
    <div className={clsx('col col--4')}>
      <div className="text--center padding-horiz--md">
        <h3>{title}</h3>
        <p>{description}</p>
      </div>
    </div>
  );
}

export default function HomepageFeatures() {
  return (
    <section className={styles.features}>
      <div className="container">
        <div className="row">
          {FeatureList.map((props, idx) => (
            <Feature key={idx} {...props} />
          ))}
        </div>
      </div>
    </section>
  );
}
